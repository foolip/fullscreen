SHELL=/bin/bash -o pipefail
.PHONY: local remote deploy r2-upload

WEB_ROOT = fullscreen.spec.whatwg.org
R2_BUCKET = whatwg-sites

remote: fullscreen.bs
	@ (HTTP_STATUS=$$(curl https://www.w3.org/publications/spec-generator/ \
	                       --output fullscreen.html \
	                       --write-out "%{http_code}" \
	                       --header "Accept: text/plain, text/html" \
	                       -F die-on=warning \
	                       -F md-Text-Macro="COMMIT-SHA LOCAL COPY" \
	                       -F file=@fullscreen.bs \
	                       -F type=bikeshed-spec \
	                       -F output=html) && \
	[[ "$$HTTP_STATUS" -eq "200" ]]) || ( \
		echo ""; cat fullscreen.html; echo ""; \
		rm -f fullscreen.html; \
		exit 22 \
	);

local: fullscreen.bs
	bikeshed spec fullscreen.bs fullscreen.html --md-Text-Macro="COMMIT-SHA LOCAL-COPY"

deploy: fullscreen.bs
	curl --remote-name --fail https://resources.whatwg.org/build/deploy.sh
	bash ./deploy.sh
	@$(MAKE) --no-print-directory r2-upload

# Uploads the output of deploy.sh to Cloudflare R2, see
# https://github.com/whatwg/misc-server/issues/107. Runs only for pushes to main
# with R2 credentials, so not for PRs. Like deploy.sh's rsync, nothing is
# deleted. Commit snapshots and review drafts are write-once (R2 bucket lock),
# so each of those directories is uploaded only if it isn't in R2 yet.
r2-upload:
	@if [[ -z "$${AWS_ACCESS_KEY_ID:-}" || "$${GITHUB_EVENT_NAME:-}" != "push" || "$${GITHUB_REF:-}" != "refs/heads/main" ]]; then \
		echo "Skipping R2 upload"; \
		exit 0; \
	fi; \
	set -o errexit; \
	echo "Uploading $(WEB_ROOT) to R2"; \
	aws s3 sync "$(WEB_ROOT)/" "s3://$(R2_BUCKET)/$(WEB_ROOT)/" \
		--exclude 'commit-snapshots/*' --exclude 'review-drafts/*'; \
	for dir in "$(WEB_ROOT)"/commit-snapshots/*/ "$(WEB_ROOT)"/review-drafts/*/; do \
		[[ -d "$$dir" ]] || continue; \
		dest="s3://$(R2_BUCKET)/$$dir"; \
		if [[ -n "$$(aws s3 ls "$$dest" || true)" ]]; then \
			echo "$$dest already exists, skipping"; \
		else \
			aws s3 sync "$$dir" "$$dest"; \
		fi; \
	done
