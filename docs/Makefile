# Makefile to convert Markdown to HTML using Pandoc

# Variables
SRC = docs.md
OUT = index.html
CSS = style.css

TOC_DEPTH = 3

all: generate

# Check if Pandoc is installed
.PHONY: check
check:
	@command -v pandoc >/dev/null 2>&1 || { echo >&2 "Pandoc is not installed. Please install it to proceed."; exit 1; }
	@echo "Pandoc is installed..."

# Default rule to create HTML from Markdown
generate: check
	@echo "Generating documentation..."
	pandoc -s --toc --toc-depth=$(TOC_DEPTH) -c $(CSS) -o $(OUT) $(SRC)
	@echo "Documentation generated as $(OUT)."

# Clean the output file
.PHONY: clean
clean:
	rm -f $(OUT)
	@echo "Cleaned up generated files."

# Help rule
.PHONY: help
help:
	@echo "Makefile for generating HTML documentation from Markdown"
	@echo "  all: Generate HTML documentation (default)"
	@echo "  clean: Remove generated files"
	@echo "  check: Check if Pandoc is installed"
	@echo "  help: Display this help message"
