package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"strconv"
)

const (
	wireVarint      = 0
	wireFixed64     = 1
	wireLengthDelim = 2
)

type ArpcRequest struct {
	Version       string
	Locale        string
	AppIdentifier string
	OsVersion     string
	FunctionId    int
	Payload       []byte
}

func CoordFromInt(n int64) float64 {
	return float64(n) * math.Pow10(-8)
}

func IntFromCoord(coord float64) int64 {
	return int64(coord * math.Pow10(8))
}

func readVarint(data []byte, idx int) (value uint64, newIdx int, ok bool) {
	var v uint64
	var shift uint
	for {
		if idx >= len(data) {
			return 0, 0, false
		}
		b := data[idx]
		idx++
		v |= uint64(b&0x7F) << shift
		if (b & 0x80) == 0 {
			return v, idx, true
		}
		shift += 7
	}
}

func readField(data []byte, idx int) (fieldNum uint64, wire uint8, dataStart int, dataEnd int, ok bool) {
	if idx >= len(data) {
		return 0, 0, 0, 0, false
	}
	tag := data[idx]
	fieldNum = uint64(tag) >> 3
	wire = tag & 0x7
	idx++

	switch wire {
	case wireVarint:
		_, newIdx, ok := readVarint(data, idx)
		if !ok {
			return 0, 0, 0, 0, false
		}
		return fieldNum, wire, idx, newIdx, true
	case wireFixed64:
		if idx+8 > len(data) {
			return 0, 0, 0, 0, false
		}
		return fieldNum, wire, idx, idx + 8, true
	case wireLengthDelim:
		length, newIdx, ok := readVarint(data, idx)
		if !ok {
			return 0, 0, 0, 0, false
		}
		if int(length) > len(data)-newIdx {
			return 0, 0, 0, 0, false
		}
		return fieldNum, wire, idx, newIdx + int(length), true
	}
	return 0, 0, 0, 0, false
}

func readPascalString(r io.Reader, remaining *int64) (string, error) {
	lengthBytes := make([]byte, 2)
	if _, err := r.Read(lengthBytes); err != nil {
		return "", err
	}
	*remaining -= 2
	length := binary.BigEndian.Uint16(lengthBytes)
	if int64(length) > *remaining {
		return "", fmt.Errorf("pascal string length %d exceeds remaining buffer size %d", length, *remaining)
	}
	str := make([]byte, length)
	if _, err := r.Read(str); err != nil {
		return "", err
	}
	*remaining -= int64(length)
	return string(str), nil
}

func ArpcDeserialize(data []byte) *ArpcRequest {
	r := bytes.NewReader(data)
	remaining := int64(len(data))

	versionBytes := make([]byte, 2)
	if _, err := r.Read(versionBytes); err != nil {
		return nil
	}
	remaining -= 2
	version := binary.BigEndian.Uint16(versionBytes)

	locale, err := readPascalString(r, &remaining)
	if err != nil {
		return nil
	}

	appIdentifier, err := readPascalString(r, &remaining)
	if err != nil {
		return nil
	}

	osVersion, err := readPascalString(r, &remaining)
	if err != nil {
		return nil
	}

	unknownBytes := make([]byte, 4)
	if _, err := r.Read(unknownBytes); err != nil {
		return nil
	}
	remaining -= 4
	functionId := int(binary.BigEndian.Uint32(unknownBytes))

	payloadLenBytes := make([]byte, 4)
	if _, err := r.Read(payloadLenBytes); err != nil {
		return nil
	}
	remaining -= 4
	payloadLen := int(binary.BigEndian.Uint32(payloadLenBytes))

	if int64(payloadLen) > remaining {
		return nil
	}
	payload := make([]byte, payloadLen)
	if _, err := r.Read(payload); err != nil {
		return nil
	}

	return &ArpcRequest{
		Version:       fmt.Sprintf("%d", version),
		Locale:        locale,
		AppIdentifier: appIdentifier,
		OsVersion:     osVersion,
		FunctionId:    functionId,
		Payload:       payload,
	}
}

func ArpcSerialize(arpc *ArpcRequest) []byte {
	buf := make([]byte, 0)

	version, _ := strconv.Atoi(arpc.Version)
	buf = append(buf, byte(version>>8), byte(version))

	buf = appendPascalString(buf, arpc.Locale)
	buf = appendPascalString(buf, arpc.AppIdentifier)
	buf = appendPascalString(buf, arpc.OsVersion)

	buf = append(buf, 0, 0, 0, 0)

	buf = appendUint32(buf, len(arpc.Payload))
	buf = append(buf, arpc.Payload...)

	return buf
}

func appendPascalString(buf []byte, s string) []byte {
	length := uint16(len(s))
	buf = append(buf, byte(length>>8), byte(length))
	buf = append(buf, s...)
	return buf
}

func appendUint32(buf []byte, v int) []byte {
	return append(buf, byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
}

func parseWifiDevice(data []byte) interface{} {
	return nil
}

func parseLocation(data []byte) interface{} {
	return nil
}

func serializeLocation(loc interface{}) []byte {
	return nil
}

func appendVarint(buf []byte, v uint64) []byte {
	for v >= 0x80 {
		buf = append(buf, byte(v)|0x80)
		v >>= 7
	}
	buf = append(buf, byte(v))
	return buf
}

func encodeZigzag(n int64) uint64 {
	if n >= 0 {
		return uint64(n) << 1
	}
	return uint64((^n+1)<<1) - 1
}

func encodeVarint(v int64) []byte {
	uv := uint64(v)
	buf := make([]byte, 0)
	for uv >= 0x80 {
		buf = append(buf, byte(uv)|0x80)
		uv >>= 7
	}
	buf = append(buf, byte(uv))
	return buf
}

func readFloat64(data []byte) float64 {
	return math.Float64frombits(binary.BigEndian.Uint64(data))
}

func writeFloat64(buf []byte, v float64) {
	binary.BigEndian.PutUint64(buf, math.Float64bits(v))
}
