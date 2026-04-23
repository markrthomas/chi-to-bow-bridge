MD_SPEC := design_spec.md
MD_INT  := integration.md
PDF_SPEC := design_spec.pdf
PDF_INT  := integration.pdf

.PHONY: all pdf clean

all: pdf

pdf: $(PDF_SPEC) $(PDF_INT)

$(PDF_SPEC): $(MD_SPEC)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD_SPEC)" -o "$(PDF_SPEC)"

$(PDF_INT): $(MD_INT)
	@command -v pandoc >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	pandoc "$(MD_INT)" -o "$(PDF_INT)"

clean:
	rm -f "$(PDF_SPEC)" "$(PDF_INT)"
