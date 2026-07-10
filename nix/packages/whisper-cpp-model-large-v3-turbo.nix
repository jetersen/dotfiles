{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "whisper-cpp-model-large-v3-turbo";
  version = "4";

  src = fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
    hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 "$src" "$out/share/whisper.cpp-model-large-v3-turbo/ggml-large-v3-turbo.bin"
    runHook postInstall
  '';

  meta = {
    description = "Whisper large-v3-turbo model converted for whisper.cpp";
    homepage = "https://huggingface.co/ggerganov/whisper.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
