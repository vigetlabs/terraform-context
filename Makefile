GITHUB_REPO := vigetlabs/terraform-context
FILES_TO_COMPRESS := descriptors.tf main.tf outputs.tf variables.tf versions.tf LICENSE LICENSE-TF-CONTEXT
GITHUB_CLI := gh

.DEFAULT_GOAL = help
EXECUTABLE_DEPS = terraform-docs gh jq

# Test for executable dependencies
K := $(foreach exec,$(EXECUTABLE_DEPS),\
				$(if $(shell which $(exec)), "$(exec) found" , $(error "No $(exec) in PATH")))

.PHONY: help docs

## This help screen
help:
	@printf "Available targets:\n\n"
	@awk '/^[a-zA-Z\-\_0-9%:\\]+/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
	gsub("\\\\", "", helpCommand); \
	gsub(":+$$", "", helpCommand); \
			printf "  \x1b[32;01m%-35s\x1b[0m %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST) | sort -u
	@printf "\n"

## Generate terraform documentation and add to README.md
docs:
	terraform-docs -c .terraform.docs.yml .

## Release a new version of the module
release: # TODO: clean this up and automate better
	# Set the release tag and version
	$(eval TAG := $(shell git describe --tags --abbrev=0))
	$(eval VERSION := $(shell git describe --tags))

	# Create a GitHub release
	$(GITHUB_CLI) release create $(VERSION) --repo $(GITHUB_REPO) --title "$(VERSION)" --notes "Release $(VERSION)" --draft

	# Compress the list of files
	mkdir -p dist
	tar -czvf dist/$(TAG).tar.gz $(FILES_TO_COMPRESS)

	# Upload the compressed archive to the GitHub release
	$(GITHUB_CLI) release upload $(VERSION) --repo $(GITHUB_REPO) dist/$(TAG).tar.gz

	clean

## Clean up generated files
clean:
	rm -rf dist
