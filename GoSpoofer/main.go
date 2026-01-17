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
	"io"
	"log"
	"math/big"
	"net/http"
	"runtime/cgo"
	"strings"
	"time"

	"github.com/elazarl/goproxy"
	pb "golocationspoofer/pb"
	"google.golang.org/protobuf/proto"
)

//#cgo CFLAGS: -DGOOS_ios -DNDEBUG
//#include <stdint.h>
//#include <stdlib.h>
import "C"

var globalCACert *tls.Certificate
var spoofLat float64 = 0.0
var spoofLon float64 = 0.0
var spoofingEnabled bool = false

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
	println("Hello from Go Location Spoofer!")
}

// golocationspoofer_init is called from Swift to set up panic recovery
//
//export golocationspoofer_init
func golocationspoofer_init() {
	println("Go Location Spoofer initialized")
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
			log.Printf("RECOVERED FROM PANIC in startproxy: %v", r)
		}
	}()

	log.Printf("Go startproxy called: lat=%f lon=%f enabled=%d", float64(lat), float64(lon), enabled)

	spoofLat = float64(lat)
	spoofLon = float64(lon)
	spoofingEnabled = enabled != 0

	log.Printf("Starting location spoofer with coords: %f, %f (enabled: %v)", spoofLat, spoofLon, spoofingEnabled)

	if certData != nil && keyData != nil {
		certPEM := C.GoString(certData)
		keyPEM := C.GoString(keyData)

		parsedCert, err := parseCA([]byte(certPEM), []byte(keyPEM))
		if err != nil {
			log.Printf("Failed to parse CA: %v", err)
			return 0
		}
		globalCACert = parsedCert
		log.Printf("CA certificate parsed successfully")
	} else {
		log.Printf("WARNING: No certificates provided, MITM disabled")
	}

	proxy := goproxy.NewProxyHttpServer()
	proxy.Verbose = true

	if globalCACert != nil {
		setupMITM(proxy, globalCACert)
		setupCertServing(proxy, globalCACert)
		log.Printf("MITM configured")
	} else {
		log.Printf("WARNING: globalCACert is nil, MITM will not work")
	}

	if spoofingEnabled {
		setupLocationSpoofing(proxy)
		log.Printf("Location spoofing configured for gs-loc.apple.com")
	}

	srv := &http.Server{
		Addr:    "127.0.0.1:8888",
		Handler: proxy,
	}

	h := cgo.NewHandle(srv)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("RECOVERED FROM PANIC in HTTP server goroutine: %v", r)
			}
		}()
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	log.Printf("HTTP server started on 127.0.0.1:8888, returning handle: %d", h)
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

func setupMITM(proxy *goproxy.ProxyHttpServer, cert *tls.Certificate) {
	customCaMitm := &goproxy.ConnectAction{
		Action:    goproxy.ConnectMitm,
		TLSConfig: goproxy.TLSConfigFromCA(cert),
	}

	var customMitmHandler goproxy.FuncHttpsHandler = func(host string, ctx *goproxy.ProxyCtx) (*goproxy.ConnectAction, string) {
		// Only MITM the location service domains
		hostname := strings.Split(host, ":")[0]
		if hostname == "gs-loc.apple.com" || hostname == "gs-loc-cn.apple.com" {
			log.Printf("MITM intercepting location service: %s", host)
			return customCaMitm, host
		}
		// For all other domains, just pass through (tunnel without MITM)
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

	proxy.OnRequest().DoFunc(func(req *http.Request, ctx *goproxy.ProxyCtx) (*http.Request, *http.Response) {
		if req.Host == "mitm.it" || req.Host == "www.mitm.it" {
			resp := goproxy.NewResponse(req, "application/x-x509-ca-cert", http.StatusOK, string(certPEM))
			resp.Header.Set("Content-Disposition", "attachment; filename=mitm-ca.crt")
			return req, resp
		}
		return req, nil
	})
}

func setupLocationSpoofing(proxy *goproxy.ProxyHttpServer) {
	proxy.OnRequest().DoFunc(func(req *http.Request, ctx *goproxy.ProxyCtx) (*http.Request, *http.Response) {
		if req.Host == "gs-loc.apple.com" || req.Host == "gs-loc-cn.apple.com" {
			if req.URL.Path == "/clls/wloc" && req.Method == "POST" {
				log.Println("Intercepting location request")
				return handleLocationRequest(req)
			}
		}
		return req, nil
	})
}

func handleLocationRequest(req *http.Request) (*http.Request, *http.Response) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("RECOVERED FROM PANIC in handleLocationRequest: %v", r)
		}
	}()

	body, err := io.ReadAll(req.Body)
	req.Body.Close()
	if err != nil {
		log.Printf("Failed to read request body: %v", err)
		return req, nil
	}

	log.Printf("Read %d bytes from request body", len(body))
	printBytes := body
	if len(printBytes) > 50 {
		printBytes = printBytes[:50]
	}
	log.Printf("First 50 bytes: %x", printBytes)

	arpc := ArpcDeserialize(body)
	if arpc == nil {
		log.Printf("Failed to deserialize ARPC")
		return req, nil
	}

	log.Printf("ARPC deserialized, payload size: %d bytes", len(arpc.Payload))

	wloc := &pb.AppleWLoc{}
	if err := proto.Unmarshal(arpc.Payload, wloc); err != nil {
		log.Printf("Failed to unmarshal protobuf: %v", err)
		return req, nil
	}

	log.Printf("Parsed AppleWLoc, wifi devices: %d", len(wloc.WifiDevices))

	lat := IntFromCoord(spoofLat)
	lon := IntFromCoord(spoofLon)
	horizontalAccuracy := int64(39)
	verticalAccuracy := int64(1000)
	altitude := int64(530)
	unknownValue4 := int64(3)
	motionActivityType := int64(63)
	motionActivityConfidence := int64(467)

	for i, device := range wloc.WifiDevices {
		log.Printf("Spoofing location for BSSID: %s (index %d)", device.GetBssid(), i)
		if device.Location == nil {
			device.Location = &pb.Location{}
		}
		device.Location.Latitude = &lat
		device.Location.Longitude = &lon
		device.Location.HorizontalAccuracy = &horizontalAccuracy
		device.Location.VerticalAccuracy = &verticalAccuracy
		device.Location.Altitude = &altitude
		device.Location.UnknownValue4 = &unknownValue4
		device.Location.MotionActivityType = &motionActivityType
		device.Location.MotionActivityConfidence = &motionActivityConfidence
	}

	wloc.NumCellResults = nil
	wloc.NumWifiResults = nil
	wloc.DeviceType = nil

	initialBytes, _ := hex.DecodeString("0001000000010000")
	responseBytes, err := SerializeProto(wloc, initialBytes)
	if err != nil {
		log.Printf("Failed to serialize protobuf: %v", err)
		return req, nil
	}
	log.Printf("Serialized spoofed AppleWLoc: %d bytes", len(responseBytes))
	log.Printf("Response bytes: %x", responseBytes)

	log.Printf("Sending spoofed response (%d bytes)", len(responseBytes))
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
