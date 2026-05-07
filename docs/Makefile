MD_SPEC := design_spec.md
MD_INT  := integration.md
MD_PLAN := PLAN.md
PDF_SPEC := design_spec.pdf
PDF_INT  := integration.pdf
PDF_PLAN := PLAN.pdf

PANDOC           ?= pandoc
PANDOC_PDF_OPTS  ?=
DOCS_ROOT        := $(abspath $(CURDIR))
PANDOC_DEFAULTS  := $(DOCS_ROOT)/pandoc-pdf-defaults.yaml
PANDOC_HDR       := $(DOCS_ROOT)/pandoc-pdf-header.tex

.PHONY: all pdf clean

all: pdf

pdf: $(PDF_SPEC) $(PDF_INT) $(PDF_PLAN)

$(PDF_SPEC): $(MD_SPEC) $(PANDOC_DEFAULTS) $(PANDOC_HDR)
	@command -v $(PANDOC) >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	$(PANDOC) --defaults "$(PANDOC_DEFAULTS)" -H "$(PANDOC_HDR)" $(PANDOC_PDF_OPTS) "$(MD_SPEC)" -o "$(PDF_SPEC)"

$(PDF_INT): $(MD_INT) $(PANDOC_DEFAULTS) $(PANDOC_HDR)
	@command -v $(PANDOC) >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	$(PANDOC) --defaults "$(PANDOC_DEFAULTS)" -H "$(PANDOC_HDR)" $(PANDOC_PDF_OPTS) "$(MD_INT)" -o "$(PDF_INT)"

$(PDF_PLAN): $(MD_PLAN) $(PANDOC_DEFAULTS) $(PANDOC_HDR)
	@command -v $(PANDOC) >/dev/null 2>&1 || (echo "Error: pandoc not found in PATH"; exit 1)
	$(PANDOC) --defaults "$(PANDOC_DEFAULTS)" -H "$(PANDOC_HDR)" $(PANDOC_PDF_OPTS) "$(MD_PLAN)" -o "$(PDF_PLAN)"

clean:
	rm -f "$(PDF_SPEC)" "$(PDF_INT)" "$(PDF_PLAN)"
