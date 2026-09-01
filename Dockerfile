FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Instalação de ferramentas base necessárias para o teste
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    git \
    wget \
    jq \
    gpg \
    ca-certificates \
    lsb-release \
    unzip \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Criação de usuário sem root para simular o ambiente de usuário real do Pop!_OS
RUN (userdel -r ubuntu 2>/dev/null || true) && \
    useradd -m -s /bin/bash -u 1000 paulogoncalves && \
    echo "paulogoncalves ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Criar diretório de mocks no PATH para utilitários que requerem hardware/display/systemd ativo
RUN mkdir -p /usr/local/mock-bin

# Mocks para comandos de hardware/desktop
RUN printf '#!/bin/bash\necho "[MOCK gsettings] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/gsettings && \
    printf '#!/bin/bash\necho "[MOCK ratbagctl] chamada: \$@"\nif [ "$1" = "list" ]; then echo "singing-hare: Logitech G502 X"; fi\nexit 0\n' > /usr/local/mock-bin/ratbagctl && \
    printf '#!/bin/bash\necho "[MOCK mount] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/mount && \
    printf '#!/bin/bash\necho "[MOCK systemctl] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/systemctl && \
    printf '#!/bin/bash\necho "[MOCK sysctl] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/sysctl && \
    printf '#!/bin/bash\necho "[MOCK espanso] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/espanso && \
    printf '#!/bin/bash\necho "[MOCK xdg-mime] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/xdg-mime && \
    printf '#!/bin/bash\nif [ "$1" = "listremotes" ]; then echo -e "onedrive_pessoal:\nmega_pessoal:\ngdrive_pessoal:"; exit 0; fi\necho "[MOCK rclone] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/rclone && \
    printf '#!/bin/bash\necho "[MOCK flatpak] chamada: \$@"\nexit 0\n' > /usr/local/mock-bin/flatpak && \
    chmod +x /usr/local/mock-bin/*

# Configurar sudoers secure_path e PATH global para que /usr/local/mock-bin seja priorizado
RUN sed -i 's|secure_path="\(.*\)"|secure_path="/usr/local/mock-bin:\1"|' /etc/sudoers && \
    echo 'export PATH="/usr/local/mock-bin:$PATH"' >> /etc/profile && \
    echo 'export PATH="/usr/local/mock-bin:$PATH"' >> /etc/bash.bashrc && \
    echo 'export PATH="/usr/local/mock-bin:$PATH"' >> /home/paulogoncalves/.bashrc

ENV PATH="/usr/local/mock-bin:${PATH}"

WORKDIR /workspace

CMD ["/bin/bash", "/workspace/test_in_docker.sh", "--inside"]
