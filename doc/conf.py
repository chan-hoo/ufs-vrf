"""Sphinx configuration for ufs-vrf documentation."""

project = "ufs-vrf"
copyright = "2026, ufs-vrf contributors"
author = "ufs-vrf contributors"

extensions = ["myst_parser"]

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

# Use Markdown for documentation pages.
source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

root_doc = "index"
html_theme = "sphinx_rtd_theme"
