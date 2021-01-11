{ 
  pkgs ? import (fetchTarball https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz) {}
}:

pkgs.stdenv.mkDerivation rec {
  name = "bpxe-shell";

  buildInputs = with pkgs; [ beam.packages.erlangR23.elixir_1_11 ];

  shellHook = ''
    export ERL_LIBS=
  '';

}


