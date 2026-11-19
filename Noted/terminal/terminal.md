find . -mindepth 2 -maxdepth 2 \
  -type f \
  \( -iname '*videoraw*' -o -iname '*audioraw*' \) \
  ! -path './.waguri-audio/*' \
  -delete



find . -mindepth 2 -maxdepth 2 -type f \
  \( -iname '*.mp4' -o -iname '*.vtt' -o -iname '*.webp' \) \
  ! -path './.waguri-audio/*' \
  -exec mv -n -t ../Main/Videos/Music/ -- {} +