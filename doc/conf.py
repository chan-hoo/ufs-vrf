"""Sphinx configuration for the UFS-VRF documentation."""

project = "Unified Forecast System Verification Framework (UFS-VRF)"
copyright = "2026, Unified Forecast System Verification Framework contributors"
author = "Unified Forecast System Verification Framework contributors"

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
