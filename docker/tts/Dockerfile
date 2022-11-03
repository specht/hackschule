FROM debian:stable

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y espeak python3 python3-pip && rm -rf /var/cache/apt/*
RUN pip3 install TTS==0.8.0
# RUN useradd -u 1000 michael
# USER michael
ENTRYPOINT tts-server --model_name tts_models/de/thorsten/tacotron2-DDC
