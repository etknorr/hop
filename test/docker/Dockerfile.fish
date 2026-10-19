# fish 3.7 from Ubuntu 24.04, with fzf 0.73.1 from the release, since the distro's 0.44.1 is below hop's 0.60.3 floor.
FROM ubuntu:24.04
ARG TARGETARCH
RUN apt-get update -qq \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends fish git ca-certificates curl bsdutils expect >/dev/null \
	&& rm -rf /var/lib/apt/lists/*
COPY fzf.sha256 /tmp/fzf.sha256
RUN curl -fsSL -o /tmp/fzf-0.73.1-linux_${TARGETARCH}.tar.gz https://github.com/junegunn/fzf/releases/download/v0.73.1/fzf-0.73.1-linux_${TARGETARCH}.tar.gz \
	&& cd /tmp && grep "linux_${TARGETARCH}.tar.gz" fzf.sha256 | sha256sum -c - \
	&& tar -xzf fzf-0.73.1-linux_${TARGETARCH}.tar.gz -C /usr/local/bin fzf && rm /tmp/fzf-* \
	&& git config --system safe.directory '*'
