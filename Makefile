YOUTUBE_URL ?= https://www.youtube.com/watch?v=dQw4w9WgXcQ

.PHONY: all build baseline baseline-safari

all: baseline-safari

build:
	xcodebuild -project isa.xcodeproj -scheme isa -configuration Debug build

baseline: build
	swift scripts/baseline_runner.swift --isa --url "$(YOUTUBE_URL)"

baseline-safari: build
	swift scripts/baseline_runner.swift --all --url "$(YOUTUBE_URL)"
