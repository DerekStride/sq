use clap::builder::{StyledStr, Styles};

pub struct HelpDoc {
    sections: Vec<HelpSection>,
}

pub struct HelpSection {
    title: &'static str,
    rows: Vec<HelpRow>,
}

pub enum HelpRow {
    Item {
        usage: &'static str,
        description: &'static str,
    },
    Text(&'static str),
}

impl HelpDoc {
    pub fn new() -> Self {
        Self {
            sections: Vec::new(),
        }
    }

    pub fn section(mut self, section: HelpSection) -> Self {
        self.sections.push(section);
        self
    }

    pub fn render(&self, styles: &Styles) -> StyledStr {
        let header = styles.get_header();
        let literal = styles.get_literal();
        let mut out = String::new();

        for (section_index, section) in self.sections.iter().enumerate() {
            if section_index > 0 {
                out.push_str("\n\n");
            }

            out.push_str(&format!("{header}{}{header:#}\n", section.title));

            let item_width = section
                .rows
                .iter()
                .filter_map(|row| match row {
                    HelpRow::Item { usage, .. } => Some(usage.chars().count()),
                    HelpRow::Text(_) => None,
                })
                .max()
                .unwrap_or(0);

            for (row_index, row) in section.rows.iter().enumerate() {
                if row_index > 0 {
                    out.push('\n');
                }

                match row {
                    HelpRow::Item { usage, description } => {
                        let padding =
                            " ".repeat(item_width.saturating_sub(usage.chars().count()) + 2);
                        out.push_str(&format!(
                            "  {literal}{usage}{literal:#}{padding}{description}"
                        ));
                    }
                    HelpRow::Text(text) => {
                        for (line_index, line) in text.lines().enumerate() {
                            if line_index > 0 {
                                out.push('\n');
                            }
                            out.push_str("  ");
                            out.push_str(line);
                        }
                    }
                }
            }
        }

        StyledStr::from(out)
    }
}

impl HelpSection {
    pub fn new(title: &'static str) -> Self {
        Self {
            title,
            rows: Vec::new(),
        }
    }

    pub fn item(mut self, usage: &'static str, description: &'static str) -> Self {
        self.rows.push(HelpRow::Item { usage, description });
        self
    }

    pub fn text(mut self, text: &'static str) -> Self {
        self.rows.push(HelpRow::Text(text));
        self
    }
}

pub fn root_after_help(styles: &Styles) -> StyledStr {
    HelpDoc::new()
        .section(
            HelpSection::new("Task file:")
                .text("By default, sq discovers the nearest existing .sift/issues.jsonl within the current git worktree and otherwise falls back to <cwd>/.sift/issues.jsonl.")
                .text("Override with -q, --queue <PATH> or SQ_QUEUE_PATH=<PATH>."),
        )
        .section(
            HelpSection::new("Workflow:")
                .item("sq list --ready", "See the next actionable tasks")
                .item("sq add --title <TITLE>", "Create a new task")
                .item("sq show <id>", "Inspect one task in detail")
                .item(
                    "sq edit <id> ...",
                    "Update fields, sources, metadata, or blockers",
                ),
        )
        .section(
            HelpSection::new("Command help:")
                .item(
                    "sq <command> --help",
                    "See command-specific guidance and examples",
                )
                .item("sq prime", "Output workflow context for AI agents"),
        )
        .render(styles)
}
