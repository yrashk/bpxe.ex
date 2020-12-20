{ 
  pkgs ? import <nixpkgs> {}
}:

pkgs.stdenv.mkDerivation rec {
  name = "bpxe-shell";

  buildInputs = with pkgs; [ elixir ];

  shellHook = ''
    export ERL_LIBS=
  '';

}


