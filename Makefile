docker:
	@docker build --no-cache . -t ethnexus/smnrp
	@docker push ethnexus/smnrp