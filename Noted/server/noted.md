server heeeyyyooo


apt update
apt upgrade -y
apt install sudo fish adduser -y
adduser shiro
usermod -aG sudo shiro
groups shiro



colab dengan xfce4

apt update
apt install -y xfce4 tigervnc-standalone-server dbus-x11

su - shiro
vncpasswd

run xfce4

vncserver :1 \
  -geometry 1280x720 \
  -depth 24 \
  -xstartup /usr/bin/startxfce4 \
  -localhost no



git clone https://github.com/novnc/noVNC.git
cd 
./utils/novnc_proxy --vnc localhost:5901 --listen localhost:6081


setup ngrok
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
  && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list \
  && sudo apt update \
  && sudo apt install ngrok


ngrok config add-authtoken $YOUR_AUTHTOKEN

ngrok http 6081 --url "urlngork"

open in u browser
