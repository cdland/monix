# System monitor. Universal (useful on servers). Theming removed in the
# simplification pass; btop uses its default theme.
{
  flake.homeModules.btop = {
    programs.btop = {
      enable = true;
      settings = {
        truecolor = true;
        vim_keys = true;
        rounded_corners = true;
        graph_symbol = "braille";
      };
    };
  };
}
