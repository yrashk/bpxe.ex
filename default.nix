{ 
  pkgs ? import <nixpkgs> {}
}:

pkgs.stdenv.mkDerivation rec {
  name = "bpex-shell";

  buildInputs = with pkgs; [ elixir ];

  shellHook = ''
    export ERL_LIBS=
  '';

}


