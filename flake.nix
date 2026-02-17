{
  description = "Ansible workspace (ephemeral tooling via devShell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              ansible
              ansible-lint
              yamllint
              python3
              python3Packages.pip
              python3Packages.virtualenv
              openssh
              sshpass
              git
              jq
              yq
            ];

            shellHook = ''
              if [ -z "''${ANSIBLE_SHELL_INIT_DONE:-}" ]; then
                export ANSIBLE_SHELL_INIT_DONE=1
                echo "→ Ansible devShell active in: $(pwd)"
                ansible --version | head -n 1 || true
                ansible-lint --version || true
                yamllint --version || true
                echo "Tip: run 'ansible-lint' and 'yamllint .' before committing."
              fi
            '';
          };
        });
    };
}
