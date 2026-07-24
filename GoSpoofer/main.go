package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"runtime/cgo"
	"strings"
	"sync"
	"time"

	"github.com/elazarl/goproxy"
	pb "golocationspoofer/pb"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/encoding/protowire"
)

//#cgo CFLAGS: -DGOOS_ios -DNDEBUG
//#include <stdint.h>
//#include <stdlib.h>
import "C"

var globalCACert *tls.Certificate
var spoofLat float64 = 0.0
var spoofLon float64 = 0.0
var spoofingEnabled bool = false

// 诊断日志环形缓冲:最近 maxLogEntries 条 logEvent 调用,带时间戳。
// drainlogs 导出函数返回缓冲内容(C 串)给 Tunnel→App 诊断面板,clear 缓冲。
const maxLogEntries = 200

var logBuffer = make([]string, 0, maxLogEntries)
var logBufferMu sync.Mutex

func logEvent(msg string) {
	stamp := time.Now().Format("15:04:05.000")
	line := stamp + "  " + msg
	logBufferMu.Lock()
	logBuffer = append(logBuffer, line)
	if len(logBuffer) > maxLogEntries {
		logBuffer = logBuffer[len(logBuffer)-maxLogEntries:]
	}
	logBufferMu.Unlock()
	// 同步写一份到 stderr(开发环境 Mac+Console.app 可见),保留原日志通路
	log.Printf("%s", msg)
}

//export golocationspoofer_drainlogs
func golocationspoofer_drainlogs() *C.char {
	logBufferMu.Lock()
	combined := strings.Join(logBuffer, "\n")
	logBuffer = logBuffer[:0]
	logBufferMu.Unlock()
	return C.CString(combined)
}

func init() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("RECOVERED FROM PANIC in init: %v", r)
		}
	}()
}

func p64(i int) *int64 {
	i64 := int64(i)
	return &i64
}

//export golocationspoofer_hello
func golocationspoofer_hello() {
}

// golocationspoofer_init is called from Swift to set up panic recovery
//
//export golocationspoofer_init
func golocationspoofer_init() {
}

//export golocationspoofer_version
func golocationspoofer_version() *C.char {
	return C.CString("1.0.0")
}

//export golocationspoofer_generateca
func golocationspoofer_generateca() (r0, r1 *C.char) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		return nil, nil
	}
	return C.CString(string(certPEM)), C.CString(string(keyPEM))
}

//export golocationspoofer_startproxy
func golocationspoofer_startproxy(certData *C.char, keyData *C.char, lat C.double, lon C.double, enabled C.int) C.uintptr_t {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("PANIC in startproxy: %v", r)
		}
	}()

	spoofLat = float64(lat)
	spoofLon = float64(lon)
	spoofingEnabled = enabled != 0

	if certData != nil && keyData != nil {
		certPEM := C.GoString(certData)
		keyPEM := C.GoString(keyData)

		parsedCert, err := parseCA([]byte(certPEM), []byte(keyPEM))
		if err != nil {
			log.Printf("Failed to parse CA cert: %v", err)
			return 0
		}
		globalCACert = parsedCert
		log.Printf("Location spoofer: MITM enabled, coordinates: %.6f, %.6f", spoofLat, spoofLon)
	}

	proxy := goproxy.NewProxyHttpServer()
	proxy.Verbose = false

	if globalCACert != nil {
		setupMITM(proxy, globalCACert)
		setupCertServing(proxy, globalCACert)
	}

	if spoofingEnabled {
		setupLocationSpoofing(proxy)
	}

	srv := &http.Server{
		Addr:    "127.0.0.1:8888",
		Handler: proxy,
	}

	h := cgo.NewHandle(srv)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("PANIC in HTTP server: %v", r)
			}
		}()
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	log.Printf("Proxy server started on 127.0.0.1:8888")
	return C.uintptr_t(h)
}

//export golocationspoofer_stopproxy
func golocationspoofer_stopproxy(h C.uintptr_t) C.int {
	handle := cgo.Handle(h)
	srv, ok := handle.Value().(*http.Server)
	if !ok {
		handle.Delete()
		return 1
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err := srv.Shutdown(ctx)
	handle.Delete()
	if err != nil {
		return 2
	}
	return 0
}

//export golocationspoofer_getcoords
func golocationspoofer_getcoords() (lat, lon C.double, enabled C.int) {
	var e C.int = 0
	if spoofingEnabled {
		e = 1
	}
	return C.double(spoofLat), C.double(spoofLon), e
}

func setupMITM(proxy *goproxy.ProxyHttpServer, cert *tls.Certificate) {
	customCaMitm := &goproxy.ConnectAction{
		Action:    goproxy.ConnectMitm,
		TLSConfig: goproxy.TLSConfigFromCA(cert),
	}

	var customMitmHandler goproxy.FuncHttpsHandler = func(host string, ctx *goproxy.ProxyCtx) (*goproxy.ConnectAction, string) {
		hostname := strings.Split(host, ":")[0]
		if hostname == "gs-loc.apple.com" || hostname == "gs-loc-cn.apple.com" {
			log.Printf("Intercepting location request: %s", host)
			return customCaMitm, host
		}
		return goproxy.OkConnect, host
	}

	proxy.OnRequest().HandleConnect(customMitmHandler)
}

func setupCertServing(proxy *goproxy.ProxyHttpServer, cert *tls.Certificate) {
	certDER := cert.Certificate[0]
	certPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certDER,
	})

	// rendoor.cert/ 收到的请求先返回这个等待页,2 秒后 meta refresh 跳 /cert 真证书。
	// 给用户视觉反馈"事情在动",避免 Safari 空白几百毫秒后突然弹下载框的突兀感。
	const waitPageHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta http-equiv="refresh" content="2;url=/cert">
<title>Preparing configuration profile</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,system-ui;background:#fff;color:#222;display:flex;flex-direction:column;justify-content:center;align-items:center;min-height:100vh;margin:0;padding:20px;text-align:center}
.title{font-size:24px;font-weight:600;margin-bottom:16px}
.subtitle{font-size:14px;color:#666;line-height:1.6;max-width:320px}
.fallback{margin-top:32px;font-size:13px}
a{color:#007AFF;text-decoration:none}
</style>
</head>
<body>
<div class="title">Preparing configuration profile…</div>
<div class="subtitle">Please wait, the system will show an install prompt shortly.<br>Do not close this page.</div>
<div class="fallback">If the prompt does not appear, <a href="/cert">tap here to download manually</a></div>
</body>
</html>`

	proxy.OnRequest().DoFunc(func(req *http.Request, ctx *goproxy.ProxyCtx) (*http.Request, *http.Response) {
		// 兼容:mitm.it 旧路径无视 path,直接返回证书。
		if req.Host == "mitm.it" || req.Host == "www.mitm.it" {
			resp := goproxy.NewResponse(req, "application/x-x509-ca-cert", http.StatusOK, string(certPEM))
			resp.Header.Set("Content-Disposition", "attachment; filename=mitm-ca.crt")
			return req, resp
		}
		// rendoor.cert:按 path 分流。/cert 真下载,其他(含 /)是 HTML 等待页。
		if req.Host == "rendoor.cert" || req.Host == "www.rendoor.cert" {
			if req.URL.Path == "/cert" {
				resp := goproxy.NewResponse(req, "application/x-x509-ca-cert", http.StatusOK, string(certPEM))
				resp.Header.Set("Content-Disposition", "attachment; filename=mitm-ca.crt")
				return req, resp
			}
			return req, goproxy.NewResponse(req, "text/html; charset=utf-8", http.StatusOK, waitPageHTML)
		}
		return req, nil
	})
}

func setupLocationSpoofing(proxy *goproxy.ProxyHttpServer) {
	proxy.OnRequest().DoFunc(func(req *http.Request, ctx *goproxy.ProxyCtx) (*http.Request, *http.Response) {
		if req.Host == "gs-loc.apple.com" || req.Host == "gs-loc-cn.apple.com" {
			if req.URL.Path == "/clls/wloc" && req.Method == "POST" {
				return handleLocationRequest(req)
			}
		}
		return req, nil
	})
}

func handleLocationRequest(req *http.Request) (*http.Request, *http.Response) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("PANIC in handleLocationRequest: %v", r)
			logEvent(fmt.Sprintf("PANIC in handleLocationRequest: %v", r))
		}
	}()

	logEvent(fmt.Sprintf("Location request received Host=%s Path=%s Method=%s", req.Host, req.URL.Path, req.Method))

	body, err := io.ReadAll(req.Body)
	req.Body.Close()
	if err != nil {
		log.Printf("Failed to read request body: %v", err)
		logEvent(fmt.Sprintf("Failed to read request body: %v, passing through", err))
		return req, nil
	}
	logEvent(fmt.Sprintf("Request body read length=%d bytes", len(body)))

	arpc := ArpcDeserialize(body)
	if arpc == nil {
		logEvent("ArpcDeserialize returned nil (possibly gzip/version mismatch), passing through")
		return req, nil
	}
	logEvent(fmt.Sprintf("ARPC parsed OK version=%s payloadLen=%d", arpc.Version, len(arpc.Payload)))

	// 仅用 proto.Unmarshal 做解析验证 + 统计 wifiCount,不再用于改写。
	wloc := &pb.AppleWLoc{}
	if err := proto.Unmarshal(arpc.Payload, wloc); err != nil {
		log.Printf("Failed to unmarshal protobuf: %v", err)
		logEvent(fmt.Sprintf("protobuf Unmarshal failed: %v, passing through", err))
		return req, nil
	}

	wifiCount := len(wloc.WifiDevices)
	log.Printf("Spoofing location for %d WiFi devices", wifiCount)
	logEvent(fmt.Sprintf("AppleWLoc parsed wifiCount=%d", wifiCount))

	// raw wire 递归 splice:只动 Location.Latitude(tag 1 varint)/Longitude(tag 2 varint)的字节,
	// 其他所有字段(HorizontalAccuracy/Altitude/未知 tag/NumCellResults/DeviceType 等)wire 字节级保留。
	lat := IntFromCoord(spoofLat)
	lon := IntFromCoord(spoofLon)
	newPayload, modifiedFields := rewriteAppleWLocCoords(arpc.Payload, lat, lon)
	logEvent(fmt.Sprintf("raw wire rewrite done in=%d B out=%d B modified %d lat/lon fields (spoof=(%.6f, %.6f))", len(arpc.Payload), len(newPayload), modifiedFields, spoofLat, spoofLon))

	// 手工构造 ARPC 响应:magic 8B + 大端 2B 长度 + payload
	initialBytes, _ := hex.DecodeString("0001000000010000")
	int16Len := make([]byte, 2)
	binary.BigEndian.PutUint16(int16Len, uint16(len(newPayload)))
	responseBytes := append(initialBytes, int16Len...)
	responseBytes = append(responseBytes, newPayload...)

	resp := &http.Response{
		Request:       req,
		StatusCode:    http.StatusOK,
		Status:        "200 OK",
		Proto:         "HTTP/1.1",
		ProtoMajor:    1,
		ProtoMinor:    1,
		Header:        make(http.Header),
		Body:          io.NopCloser(bytes.NewReader(responseBytes)),
		ContentLength: int64(len(responseBytes)),
	}
	resp.Header.Set("Content-Type", "application/octet-stream")
	logEvent(fmt.Sprintf("Response sent 200 OK respLen=%d wifiCount=%d", len(responseBytes), wifiCount))
	return req, resp
}

func generateCA() (certPEM, keyPEM []byte, err error) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, err
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization:  []string{"Location Spoofer"},
			Country:       []string{"US"},
			Province:      []string{""},
			Locality:      []string{""},
			StreetAddress: []string{""},
			PostalCode:    []string{""},
			CommonName:    "Location Spoofer CA",
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, &template, &template, &privateKey.PublicKey, privateKey)
	if err != nil {
		return nil, nil, err
	}

	certPEM = pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certDER,
	})

	privateKeyDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		return nil, nil, err
	}

	keyPEM = pem.EncodeToMemory(&pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: privateKeyDER,
	})

	return certPEM, keyPEM, nil
}

func parseCA(caCert, caKey []byte) (*tls.Certificate, error) {
	parsedCert, err := tls.X509KeyPair(caCert, caKey)
	if err != nil {
		return nil, err
	}
	if parsedCert.Leaf, err = x509.ParseCertificate(parsedCert.Certificate[0]); err != nil {
		return nil, err
	}
	return &parsedCert, nil
}

func SerializeProto(p proto.Message, initial []byte) ([]byte, error) {
	if p == nil {
		panic("protobuf is nil")
	}
	b, err := proto.Marshal(p)
	if err != nil {
		return nil, err
	}
	int16Len := make([]byte, 2)
	binary.BigEndian.PutUint16(int16Len, uint16(len(b)))
	if initial != nil {
		b = append(initial, append(int16Len, b...)...)
	}
	return b, nil
}

func main() {}
// rewriteAppleWLocCoords 在 AppleWLoc 原始 wire bytes 上扫描所有 WifiDevices(tag=2 LEN),
// 对每个 WifiDevice 递归调用 rewriteWifiDevice 把 lat/lon 改成 spoof 坐标。
// 其他顶层字段(NumCellResults/CellTowerResponse/DeviceType/未知 tag 等)wire 字节级原样保留。
// 解析失败原样返回(透传),由调用方继续走 Apple 真响应路径。
func rewriteAppleWLocCoords(payload []byte, lat, lon int64) ([]byte, int) {
	out := make([]byte, 0, len(payload))
	modified := 0
	b := payload
	for len(b) > 0 {
		num, typ, tagLen := protowire.ConsumeTag(b)
		if tagLen < 0 {
			return payload, modified
		}
		if num == 2 && typ == protowire.BytesType {
			wdBytes, valLen := protowire.ConsumeBytes(b[tagLen:])
			if valLen < 0 {
				return payload, modified
			}
			newWd, sub := rewriteWifiDevice(wdBytes, lat, lon)
			modified += sub
			out = protowire.AppendTag(out, 2, protowire.BytesType)
			out = protowire.AppendBytes(out, newWd)
			b = b[tagLen+valLen:]
		} else {
			n := protowire.ConsumeFieldValue(num, typ, b[tagLen:])
			if n < 0 {
				return payload, modified
			}
			out = append(out, b[:tagLen+n]...)
			b = b[tagLen+n:]
		}
	}
	return out, modified
}

// rewriteWifiDevice 在 WifiDevice wire bytes 上找 Location(tag=2 LEN)子消息执行替换。
// 若 WifiDevice 不含 Location(请求侧通常如此),则在末尾注入完整新 Location(只含 lat/lon),
// 匹配 upstream Unmarshal 路径的 `if device.Location == nil { device.Location = &pb.Location{} }` 语义。
// 其他字段(Bssid 等)wire 字节级保留。
func rewriteWifiDevice(wd []byte, lat, lon int64) ([]byte, int) {
	out := make([]byte, 0, len(wd)+24)
	modified := 0
	locationSeen := false
	b := wd
	for len(b) > 0 {
		num, typ, tagLen := protowire.ConsumeTag(b)
		if tagLen < 0 {
			return wd, modified
		}
		if num == 2 && typ == protowire.BytesType {
			locationSeen = true
			locBytes, valLen := protowire.ConsumeBytes(b[tagLen:])
			if valLen < 0 {
				return wd, modified
			}
			newLoc, sub := rewriteLocation(locBytes, lat, lon)
			modified += sub
			out = protowire.AppendTag(out, 2, protowire.BytesType)
			out = protowire.AppendBytes(out, newLoc)
			b = b[tagLen+valLen:]
		} else {
			n := protowire.ConsumeFieldValue(num, typ, b[tagLen:])
			if n < 0 {
				return wd, modified
			}
			out = append(out, b[:tagLen+n]...)
			b = b[tagLen+n:]
		}
	}
	if !locationSeen {
		var loc []byte
		loc = protowire.AppendTag(loc, 1, protowire.VarintType)
		loc = protowire.AppendVarint(loc, uint64(lat))
		loc = protowire.AppendTag(loc, 2, protowire.VarintType)
		loc = protowire.AppendVarint(loc, uint64(lon))
		out = protowire.AppendTag(out, 2, protowire.BytesType)
		out = protowire.AppendBytes(out, loc)
		modified += 2
	}
	return out, modified
}

// rewriteLocation 在 Location wire bytes 上替换 Latitude(tag=1 varint)和 Longitude(tag=2 varint)。
// 缺失字段会被注入。其他字段(HorizontalAccuracy/Altitude/未知 tag 等)wire 字节级原样保留。
// int64 转 varint 用 uint64 重解释(protobuf int64 varint 编码规则)。
func rewriteLocation(loc []byte, lat, lon int64) ([]byte, int) {
	out := make([]byte, 0, len(loc)+20)
	modified := 0
	latSeen := false
	lonSeen := false
	b := loc
	for len(b) > 0 {
		num, typ, tagLen := protowire.ConsumeTag(b)
		if tagLen < 0 {
			return loc, modified
		}
		if num == 1 && typ == protowire.VarintType {
			latSeen = true
			_, valLen := protowire.ConsumeVarint(b[tagLen:])
			if valLen < 0 {
				return loc, modified
			}
			out = protowire.AppendTag(out, 1, protowire.VarintType)
			out = protowire.AppendVarint(out, uint64(lat))
			b = b[tagLen+valLen:]
			modified++
		} else if num == 2 && typ == protowire.VarintType {
			lonSeen = true
			_, valLen := protowire.ConsumeVarint(b[tagLen:])
			if valLen < 0 {
				return loc, modified
			}
			out = protowire.AppendTag(out, 2, protowire.VarintType)
			out = protowire.AppendVarint(out, uint64(lon))
			b = b[tagLen+valLen:]
			modified++
		} else {
			n := protowire.ConsumeFieldValue(num, typ, b[tagLen:])
			if n < 0 {
				return loc, modified
			}
			out = append(out, b[:tagLen+n]...)
			b = b[tagLen+n:]
		}
	}
	if !latSeen {
		out = protowire.AppendTag(out, 1, protowire.VarintType)
		out = protowire.AppendVarint(out, uint64(lat))
		modified++
	}
	if !lonSeen {
		out = protowire.AppendTag(out, 2, protowire.VarintType)
		out = protowire.AppendVarint(out, uint64(lon))
		modified++
	}
	return out, modified
}

