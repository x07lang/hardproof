.PHONY: refresh-example-artifacts refresh-example-artifacts-check

refresh-example-artifacts:
	./scripts/refresh_example_artifacts.sh

refresh-example-artifacts-check:
	./scripts/refresh_example_artifacts.sh --check
