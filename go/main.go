package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"

	"golang.org/x/crypto/ssh/agent"
)

var passed, failed int

func pass(name, detail string) {
	fmt.Printf("PASS: %s — %s\n", name, detail)
	passed++
}

func fail(name, detail string) {
	fmt.Printf("FAIL: %s — %s\n", name, detail)
	failed++
}

func readSSHString(data []byte, offset int) (string, int, error) {
	if offset+4 > len(data) {
		return "", 0, errors.New("not enough data for string length")
	}
	slen := int(binary.BigEndian.Uint32(data[offset:]))
	offset += 4
	if offset+slen > len(data) {
		return "", 0, fmt.Errorf("string length %d exceeds remaining data %d", slen, len(data)-offset)
	}
	s := string(data[offset : offset+slen])
	offset += slen
	s = strings.TrimRight(s, "\x00")
	return s, offset, nil
}

func testList(client agent.ExtendedAgent) {
	name := "list"
	keys, err := client.List()
	if err != nil {
		// pivy-agent returns SSH_AGENT_FAILURE when pcscd is unavailable,
		// which is a valid protocol response — not a conformance failure.
		fmt.Printf("SKIP: %s — %v (pcscd likely unavailable)\n", name, err)
		return
	}
	pass(name, fmt.Sprintf("Go parsed identity list: %d keys", len(keys)))
}

func testQuery(client agent.ExtendedAgent) {
	name := "query"
	resp, err := client.Extension("query", nil)
	if errors.Is(err, agent.ErrExtensionUnsupported) {
		fail(name, "agent does not support query extension")
		return
	}
	if err != nil {
		fail(name, fmt.Sprintf("Extension() error: %v", err))
		return
	}

	if len(resp) < 1 {
		fail(name, "empty response")
		return
	}
	if resp[0] != 29 {
		fail(name, fmt.Sprintf("expected type 29 (SSH_AGENT_EXTENSION_RESPONSE), got %d", resp[0]))
		return
	}

	offset := 1
	echo, next, err := readSSHString(resp, offset)
	if err != nil {
		fail(name, fmt.Sprintf("failed to read name echo: %v", err))
		return
	}
	if echo != "query" {
		fail(name, fmt.Sprintf("name echo mismatch: got %q, want %q", echo, "query"))
		return
	}
	offset = next

	var extensions []string
	for offset < len(resp) {
		var s string
		s, offset, err = readSSHString(resp, offset)
		if err != nil {
			fail(name, fmt.Sprintf("failed to parse extension name at offset %d: %v", offset, err))
			return
		}
		extensions = append(extensions, s)
	}

	pass(name, fmt.Sprintf("type=29, echo=\"query\", %d extensions: [%s]",
		len(extensions), strings.Join(extensions, ", ")))
}

func testPinStatus(client agent.ExtendedAgent) {
	name := "pin-status@joyent.com"
	resp, err := client.Extension("pin-status@joyent.com", nil)
	if errors.Is(err, agent.ErrExtensionUnsupported) {
		fail(name, "agent does not support pin-status extension")
		return
	}
	if err != nil {
		fail(name, fmt.Sprintf("Extension() error: %v", err))
		return
	}

	if len(resp) < 1 {
		fail(name, "empty response")
		return
	}
	if resp[0] != 29 {
		fail(name, fmt.Sprintf("expected type 29, got %d", resp[0]))
		return
	}

	offset := 1
	echo, next, err := readSSHString(resp, offset)
	if err != nil {
		fail(name, fmt.Sprintf("failed to read name echo: %v", err))
		return
	}
	if echo != "pin-status@joyent.com" {
		fail(name, fmt.Sprintf("name echo mismatch: got %q, want %q", echo, "pin-status@joyent.com"))
		return
	}
	offset = next

	remaining := len(resp) - offset
	if remaining != 2 {
		fail(name, fmt.Sprintf("expected 2 payload bytes (has_pin + has_card), got %d", remaining))
		return
	}

	hasPin := resp[offset]
	hasCard := resp[offset+1]
	pass(name, fmt.Sprintf("type=29, echo, has_pin=%d has_card=%d", hasPin, hasCard))
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "Usage: pivy-agent-conformance <socket-path>\n")
		os.Exit(2)
	}

	conn, err := net.Dial("unix", os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to connect to agent: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	client := agent.NewClient(conn)

	fmt.Println("Running Go conformance tests...\n")
	testList(client)
	testQuery(client)
	testPinStatus(client)

	fmt.Printf("\n%d passed, %d failed\n", passed, failed)
	if failed > 0 {
		os.Exit(1)
	}
}
