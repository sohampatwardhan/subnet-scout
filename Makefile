.PHONY: test generate

test:
	swift test

generate:
	cd App && xcodegen generate
