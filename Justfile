set quiet

# List available recipes
default:
    just --list --unsorted

# Build the command-line tool
build:
    go build -o bin/mjc .

# Format Go sources
fmt:
    gofmt -w *.go

# Check formatting without changing files
fmt-check:
    #!/usr/bin/env sh
    set -eu
    unformatted=$(gofmt -l *.go)
    if [ -n "$unformatted" ]; then
        printf 'Run just fmt to format:\n%s\n' "$unformatted"
        exit 1
    fi

# Run regression tests
test:
    go test ./...

# Run Go static analysis
vet:
    go vet ./...

# Check formatting, tests, and static analysis
check: fmt-check test vet

# Run codec benchmarks (three samples by default)
[positional-arguments]
bench count="3":
    go test -run='^$' -bench=. -benchmem -count="$1"

# Fuzz round trips for the given duration
[positional-arguments]
fuzz duration="10s":
    go test -run='^$' -fuzz=FuzzRoundTrip -fuzztime="$1"

# Compress a file
[positional-arguments]
compress input output:
    go run . c "$1" "$2"

# Decompress an archive
[positional-arguments]
decompress input output:
    go run . d "$1" "$2"

# Regenerate the checked-in sample archive
sample:
    go run . c input.txt output.txt

# Remove the compiled binary
clean:
    rm -f bin/mjc
