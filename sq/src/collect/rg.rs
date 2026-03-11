use crate::collect::GroupedItem;
use anyhow::{anyhow, bail, Result};

pub fn parse_json(input: &str) -> Result<Vec<GroupedItem>> {
    let mut items = Vec::new();
    let mut current: Option<GroupedItem> = None;

    for (index, raw_line) in input.lines().enumerate() {
        let line_number = index + 1;
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let value: serde_json::Value = serde_json::from_str(line)
            .map_err(|e| anyhow!("invalid rg --json input on line {}: {}", line_number, e))?;

        let event_type = value.get("type").and_then(|v| v.as_str()).ok_or_else(|| {
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
                current = Some(GroupedItem {
                    filepath,
                    text: String::new(),
                    match_count: 0,
                });
            }
            "match" | "context" => {
                let filepath = path_from_value(&value).ok_or_else(|| {
                    anyhow!(
                        "invalid rg --json input on line {}: missing path",
                        line_number
                    )
                })?;
                if current.as_ref().map(|item| item.filepath.as_str()) != Some(filepath.as_str()) {
                    finalize(&mut current, &mut items);
                    current = Some(GroupedItem {
                        filepath: filepath.clone(),
                        text: String::new(),
                        match_count: 0,
                    });
                }

                let rendered = render_line(&value);
                if let Some(item) = current.as_mut() {
                    if !item.text.is_empty() {
                        item.text.push('\n');
                    }
                    item.text.push_str(&rendered);
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

fn finalize(current: &mut Option<GroupedItem>, items: &mut Vec<GroupedItem>) {
    if let Some(item) = current.take() {
        if !item.text.is_empty() {
            items.push(item);
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

fn render_line(value: &serde_json::Value) -> String {
    let text = value
        .get("data")
        .and_then(|data| data.get("lines"))
        .and_then(|lines| lines.get("text"))
        .and_then(|text| text.as_str())
        .unwrap_or("")
        .trim_end_matches('\n');

    let line_number = value
        .get("data")
        .and_then(|data| data.get("line_number"))
        .and_then(|n| n.as_u64());

    match line_number {
        Some(number) if !text.is_empty() => format!("{}: {}", number, text),
        Some(number) => format!("{}:", number),
        None => text.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn test_parse_rg_json_ignores_summary() {
        let input = concat!(
            "{\"type\":\"summary\",\"data\":{}}\n",
            "{\"type\":\"begin\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n",
            "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"a.rb\"},\"lines\":{\"text\":\"foo\\n\"},\"line_number\":1}}\n",
            "{\"type\":\"end\",\"data\":{\"path\":{\"text\":\"a.rb\"}}}\n"
        );

        let parsed = parse_json(input).unwrap();
        assert_eq!(parsed.len(), 1);
    }
}
