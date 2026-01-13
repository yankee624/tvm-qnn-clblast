FROM nvcr.io/nvidia/pytorch:24.10-py3

# Install basic dependencies.
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    gdb \
    curl \
    git \
    gnupg \
    unzip \
    wget \
    zip \
    graphviz \
    doxygen \
    vim \
    clinfo \
    libncurses5-dev


# Install java
RUN wget https://download.oracle.com/java/21/archive/jdk-21.0.3_linux-x64_bin.deb -O /tmp/jdk-21.0.3_linux-x64_bin.deb && \
    dpkg -i /tmp/jdk-21.0.3_linux-x64_bin.deb && \
    rm /tmp/jdk-21.0.3_linux-x64_bin.deb

# Install Android SDK/NDK
ENV JAVA_HOME /usr/lib/jvm/jdk-21-oracle-x64
ENV PATH ${JAVA_HOME}/bin:${PATH}
ENV ANDROID_HOME /opt/android
ENV ANDROID_API_LEVEL 33
ENV ANDROID_NDK_API_LEVEL 25
ENV ANDROID_NDK_VERSION 25.2.9519653
ENV ANDROID_BUILD_TOOLS_VERSION 33.0.2
ENV ANDROID_SDK_HOME ${ANDROID_HOME}
ENV ANDROID_NDK_HOME ${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}
ENV ANDROID_NDK_ROOT ${ANDROID_NDK_HOME}
ENV PATH ${ANDROID_NDK_HOME}:${PATH}
RUN mkdir -p ${ANDROID_HOME}
RUN wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/commandlinetools.zip && \
    unzip /tmp/commandlinetools.zip -d /opt/android && \
    rm /tmp/commandlinetools.zip
RUN yes | ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses
RUN ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} "platforms;android-${ANDROID_API_LEVEL}" "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" "ndk;${ANDROID_NDK_VERSION}" "platform-tools"
ENV PATH ${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/ndk:${PATH}
RUN chmod -R go=u ${ANDROID_HOME}

# Install bazel
RUN wget https://github.com/bazelbuild/bazelisk/releases/download/v1.19.0/bazelisk-linux-amd64 -O /usr/local/bin/bazel && \
    chmod +x /usr/local/bin/bazel

# Get buildifier to format bazel-related files.
RUN wget https://github.com/bazelbuild/buildtools/releases/download/v6.4.0/buildifier-linux-amd64 -O /usr/local/bin/buildifier && \
    chmod +x /usr/local/bin/buildifier

# Install clang-format and clang-tidy
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc
RUN echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-18 main" >> /etc/apt/sources.list
RUN apt-get update && apt-get install -y clang-format-18 clang-tidy-18
RUN ln -s /usr/bin/clang-format-18 /usr/bin/clang-format
RUN ln -s /usr/bin/clang-tidy-18 /usr/bin/clang-tidy

# Install python
RUN apt-get install -y python3 python3-pip
RUN pip3 install --upgrade pip

# Install mkdocs
RUN pip3 install mkdocs mkdocs-material

# Install pre-commit
RUN pip3 install pre-commit

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash Miniconda3-latest-Linux-x86_64.sh -b -p /opt/conda \
    && rm Miniconda3-latest-Linux-x86_64.sh
ENV PATH /opt/conda/bin:${PATH}


# Install Vulkan SDK
# RUN wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | apt-key add -
# RUN wget -qO /etc/apt/sources.list.d/lunarg-vulkan-1.4.313-noble.list https://packages.lunarg.com/vulkan/1.4.313/lunarg-vulkan-1.4.313-noble.list
# RUN apt update
# RUN apt install -y vulkan-sdk

# Nvidia OpenCL ICD setup
RUN mkdir -p /etc/OpenCL/vendors
RUN apt-get install -y ocl-icd-opencl-dev
RUN echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd

# Nvidia Vulkan ICD setup
# ENV NVIDIA_DRIVER_CAPABILITIES all
# RUN apt-get install -y \
#     libxext6 \
#     libvulkan1 \
#     libvulkan-dev \
#     vulkan-tools
# RUN mkdir -p /etc/vulkan/icd.d
# RUN echo "{\"file_format_version\":\"1.0.0\",\"ICD\":{\"library_path\":\"libGLX_nvidia.so.0\",\"api_version\":\"1.3\"}}" > /etc/vulkan/icd.d/nvidia.icd

# Qualcomm Hexagon SDK setup
RUN curl -L https://softwarecenter.qualcomm.com/api/download/software/tools/Qualcomm_Software_Center/Linux/Debian/1.17.2/QualcommSoftwareCenter1.17.2.Linux-x86.deb -o /tmp/qsc_installer.deb
RUN mkdir /tmp/qsc_extracted \
 && dpkg --fsys-tarfile /tmp/qsc_installer.deb | tar -C /tmp/qsc_extracted -xf -
RUN rm /tmp/qsc_installer.deb

# Qualcomm AI Runtime setup
RUN curl -L https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/2.40.0.251030/v2.40.0.251030.zip -o /opt/v2.40.0.251030.zip
RUN unzip /opt/v2.40.0.251030.zip -d /opt/ && rm /opt/v2.40.0.251030.zip
ENV QAIRT_SDK_ROOT /opt/qairt/2.40.0.251030
RUN source ${QAIRT_SDK_ROOT}/bin/envsetup.sh
RUN ${QAIRT_SDK_ROOT}/bin/check-linux-dependency.sh
RUN ${QAIRT_SDK_ROOT}/bin/envcheck -c

# Some tricks for sudo
RUN echo -e '#!/bin/sh\nexec "$@"' > /usr/bin/sudo
RUN chmod +x /usr/bin/sudo

RUN mkdir -p /tmp/qcom
RUN mkdir -p /opt/qcom
RUN mkdir -p /var/lib/qcom
RUN mkdir -p /var/tmp/qcom
RUN cp -r /tmp/qsc_extracted/opt/qcom/* /opt/qcom/
RUN cp -r /tmp/qsc_extracted/tmp/qcom/* /tmp/qcom/
RUN bash /tmp/qcom/qsc_installer/prepare_qsc.sh
RUN ln -fs /opt/qcom/softwarecenter/bin/qpm-cli/qpm-cli /usr/bin/qpm-cli
RUN ln -fs /opt/qcom/softwarecenter/bin/qik/qik /usr/bin/qikv3
RUN ln -fs /opt/qcom/softwarecenter/bin/qik/qik /var/lib/qcom/bin/qikv3
RUN ln -fs /opt/qcom/softwarecenter/bin/qsc-cli/qsc-cli /usr/bin/qsc-cli

ENV HEXAGON_SDK_VERSION 6.3.0.0
ENV HEXAGON_TOOLS_SEMANTIC_VERSION 8.8.06
ENV HEXAGON_SDK_ROOT /local/mnt/workspace/Qualcomm/Hexagon_SDK/${HEXAGON_SDK_VERSION}
ENV HEXAGON_TOOLS_ROOT ${HEXAGON_SDK_ROOT}/tools/HEXAGON_Tools/${HEXAGON_TOOLS_SEMANTIC_VERSION}
ENV HEXAGON_ARCH v75
ENV HEXAGON_TOOLS_VERSION v88