use crate::collect::GroupedItem;
use anyhow::{anyhow, bail, Result};

pub fn parse_json(input: &str) -> Result<Vec<GroupedItem>> {
    let mut items = Vec::new();
    let mut current: Option<ActiveGroup> = None;

    for (index, raw_line) in input.lines().enumerate() {
        let line_number = index + 1;
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let value: serde_json::Value = serde_json::from_str(line)
            .map_err(|e| anyhow!("invalid rg --json input on line {}: {}", line_number, e))?;

        let event_type = value
            .get("type")
            .and_then(|value| value.as_str())
            .ok_or_else(|| {
                anyhow!(
                    "invalid rg --json input on line {}: missing type",
                    line_number
                )
            })?;

        match event_type {
            "begin" => {
                finalize(&mut current, &mut items);
                let filepath = path_from_value(&value).ok_or_else(|| {
                    anyhow!(
                        "invalid rg --json input on line {}: missing path",
                        line_number
                    )
                })?;
                current = Some(ActiveGroup::new(filepath));
            }
            "match" | "context" => {
                let filepath = path_from_value(&value).ok_or_else(|| {
                    anyhow!(
                        "invalid rg --json input on line {}: missing path",
                        line_number
                    )
                })?;
                let lines_text = lines_text_from_value(&value).ok_or_else(|| {
                    anyhow!(
                        "invalid rg --json input on line {}: missing lines.text",
                        line_number
                    )
                })?;
                let line_number = value
                    .get("data")
                    .and_then(|data| data.get("line_number"))
                    .and_then(|number| number.as_u64());

                if current.as_ref().map(|item| item.filepath.as_str()) != Some(filepath.as_str()) {
                    finalize(&mut current, &mut items);
                    current = Some(ActiveGroup::new(filepath));
                }

                if let Some(item) = current.as_mut() {
                    item.push_text(&lines_text, line_number);
                    if event_type == "match" {
                        item.match_count += 1;
                    }
                }
            }
            "end" => {
                if let Some(filepath) = path_from_value(&value) {
                    if current.as_ref().map(|item| item.filepath.as_str())
                        != Some(filepath.as_str())
                    {
                        finalize(&mut current, &mut items);
                    }
                }
                finalize(&mut current, &mut items);
            }
            "summary" => {}
            _ => {}
        }
    }

    finalize(&mut current, &mut items);

    if items.is_empty() {
        bail!("no rg matches found in stdin");
    }

    Ok(items)
}

#[derive(Debug, Clone)]
struct ActiveGroup {
    filepath: String,
    lines: Vec<String>,
    match_count: usize,
    last_line_number: Option<u64>,
}

impl ActiveGroup {
    fn new(filepath: String) -> Self {
        Self {
            filepath,
            lines: Vec::new(),
            match_count: 0,
            last_line_number: None,
        }
    }

    fn push_text(&mut self, text: &str, line_number: Option<u64>) {
        let split_lines = split_rg_text_lines(text);
        if split_lines.is_empty() {
            return;
        }

        if let (Some(previous), Some(start)) = (self.last_line_number, line_number) {
            if start > previous + 1
                && !self.lines.is_empty()
                && self.lines.last() != Some(&String::new())
            {
                self.lines.push(String::new());
            }
        }

        match line_number {
            Some(start) => {
                for (offset, line) in split_lines.iter().enumerate() {
                    self.lines
                        .push(format!("{}: {}", start + offset as u64, line));
                }
                self.last_line_number = Some(start + split_lines.len() as u64 - 1);
            }
            None => {
                self.lines.extend(split_lines);
                self.last_line_number = None;
            }
        }
    }

    fn into_grouped_item(self) -> GroupedItem {
        GroupedItem {
            filepath: self.filepath,
            text: self.lines.join("\n"),
            match_count: self.match_count,
        }
    }
}

fn finalize(current: &mut Option<ActiveGroup>, items: &mut Vec<GroupedItem>) {
    if let Some(item) = current.take() {
        if !item.lines.is_empty() {
            items.push(item.into_grouped_item());
        }
    }
}

fn path_from_value(value: &serde_json::Value) -> Option<String> {
    value
        .get("data")
        .and_then(|data| data.get("path"))
        .and_then(|path| path.get("text"))
        .and_then(|text| text.as_str())
        .map(|text| text.to_string())
}

fn lines_text_from_value(value: &serde_json::Value) -> Option<String> {
    value
        .get("data")
        .and_then(|data| data.get("lines"))
        .and_then(|lines| lines.get("text"))
        .and_then(|text| text.as_str())
        .map(|text| text.to_string())
}

fn split_rg_text_lines(text: &str) -> Vec<String> {
    let mut lines: Vec<String> = text.split('\n').map(|line| line.to_string()).collect();
    if text.ends_with('\n') {
        lines.pop();
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::parse_json;

    #[test]
    fn test_parse_rg_json_single_file() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].filepath, "a.rb");
        assert_eq!(parsed[0].text, "1: foo");
        assert_eq!(parsed[0].match_count, 1);
    }

    #[test]
    fn test_parse_rg_json_multi_file() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"b.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"b.rb\"},\"lines\":{\"text\":\"bar\\n\"},\"line_number\":7}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"b.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].filepath, "a.rb");
        assert_eq!(parsed[1].filepath, "b.rb");
    }

    #[test]
    fn test_parse_rg_json_with_context() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"before\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":2}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"after\\n\"},\"line_number\":3}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed[0].text, "1: before\n2: foo\n3: after");
        assert_eq!(parsed[0].match_count, 1);
    }

    #[test]
    fn test_parse_rg_json_preserves_blank_context_lines() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"\\n\"},\"line_number\":2}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":3}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed[0].text, "2: \n3: foo");
    }

    #[test]
    fn test_parse_rg_json_adds_spacing_between_separate_match_groups() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"before first\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"first\\n\"},\"line_number\":2}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"after first\\n\"},\"line_number\":3}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"before second\\n\"},\"line_number\":10}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"second\\n\"},\"line_number\":11}}\n",
            "{\"type\":\"context\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"after second\\n\"},\"line_number\":12}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(
            parsed[0].text,
            "1: before first\n2: first\n3: after first\n\n10: before second\n11: second\n12: after second"
        );
        assert_eq!(parsed[0].match_count, 2);
    }

    #[test]
    fn test_parse_rg_json_ignores_summary() {
        let input = concat!(
            "{\"type\":\"summary\",\"data\":{\"elapsed_total\":{\"human\":\"0.1s\"}}}\n",
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].filepath, "a.rb");
    }

    #[test]
    fn test_parse_rg_json_empty_reports_no_matches() {
        let err = parse_json("").unwrap_err();
        assert!(err.to_string().contains("no rg matches found"));
    }

    #[test]
    fn test_parse_rg_json_invalid_line_reports_line_number() {
        let err = parse_json("not json\n").unwrap_err();
        assert!(err.to_string().contains("line 1"));
    }

    #[test]
    fn test_parse_rg_json_missing_begin_path_fails() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n"
        );

        let err = parse_json(input).unwrap_err();
        assert!(err.to_string().contains("line 1"));
        assert!(err.to_string().contains("missing path"));
    }

    #[test]
    fn test_parse_rg_json_missing_lines_text_fails() {
        let input = concat!(
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"line_number\":1}}\n"
        );

        let err = parse_json(input).unwrap_err();
        assert!(err.to_string().contains("line 2"));
        assert!(err.to_string().contains("missing lines.text"));
    }
}
