FROM --platform=linux/amd64 ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y git gcc g++ cmake make nodejs npm*
RUN npm install -g tree-sitter-cli
WORKDIR /workspace
CMD ["bash"]
