# Session 10: a practice "VM" — Ubuntu 24.04 with systemd and SSH, run as a container.
# It behaves like a small server: Ansible logs in over SSH and manages systemd services.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus openssh-server sudo \
      python3 python3-venv python3-packaging ca-certificates curl nginx logrotate \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
# The image already has a user "ubuntu" (uid 1000): give it sudo without a password, like a cloud VM.
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu && chmod 440 /etc/sudoers.d/ubuntu \
 && mkdir -p /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && chown ubuntu:ubuntu /home/ubuntu/.ssh \
 && systemctl enable ssh \
 && systemctl disable nginx
EXPOSE 22 80
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
