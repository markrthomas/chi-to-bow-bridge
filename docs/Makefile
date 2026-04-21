MD := design_spec.md
PDF := design_spec.pdf

.PHONY: all pdf clean

all: pdf

pdf: $(PDF)

$(PDF): $(MD)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD)" -o "$(PDF)"

clean:
	rm -f "$(PDF)"
