build:
	@docker build --no-cache . -t ethnexus/smnrp
docker: build
	@docker push ethnexus/smnrp