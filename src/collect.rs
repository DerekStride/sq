pub mod rg;

use anyhow::Result;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    RgJson,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupedItem {
    pub filepath: String,
    pub text: String,
    pub match_count: usize,
}

pub fn detect_format(input: &str) -> Option<Format> {
    let first_line = input.lines().find(|line| !line.trim().is_empty())?;
    let value = serde_json::from_str::<serde_json::Value>(first_line).ok()?;
    match value.get("type").and_then(|value| value.as_str()) {
        Some(_) => Some(Format::RgJson),
        None => None,
    }
}

pub fn filename_for(filepath: &str) -> &str {
    std::path::Path::new(filepath)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(filepath)
}

pub fn render_title(
    title: Option<&str>,
    title_template: Option<&str>,
    item: &GroupedItem,
) -> Result<String> {
    let template = title_template.unwrap_or("{{match_count}}:{{filepath}}");

    if title_template.is_some() {
        let rendered = template
            .replace("{{filepath}}", &item.filepath)
            .replace("{{filename}}", filename_for(&item.filepath))
            .replace("{{match_count}}", &item.match_count.to_string());
        return Ok(rendered);
    }

    if let Some(title) = title {
        return Ok(title.to_string());
    }

    Ok(template
        .replace("{{filepath}}", &item.filepath)
        .replace("{{filename}}", filename_for(&item.filepath))
        .replace("{{match_count}}", &item.match_count.to_string()))
}

#[cfg(test)]
mod tests {
    use super::{detect_format, render_title, Format, GroupedItem};

    fn grouped_item() -> GroupedItem {
        GroupedItem {
            filepath: "lib/a.rb".to_string(),
            text: "1: foo".to_string(),
            match_count: 2,
        }
    }

    #[test]
    fn test_detect_format_rg_json() {
        let input = r#"{"type":"begin","data":{"path":{"text":"lib/a.rb"}}}"#;
        assert_eq!(detect_format(input), Some(Format::RgJson));
    }

    #[test]
    fn test_detect_format_unknown() {
        assert_eq!(detect_format("not json"), None);
    }

    #[test]
    fn test_render_title_template_filepath() {
        assert_eq!(
            render_title(None, Some("{{filepath}}"), &grouped_item()).unwrap(),
            "lib/a.rb"
        );
    }

    #[test]
    fn test_render_title_template_filename() {
        assert_eq!(
            render_title(None, Some("{{filename}}"), &grouped_item()).unwrap(),
            "a.rb"
        );
    }

    #[test]
    fn test_render_title_template_match_count() {
        assert_eq!(
            render_title(None, Some("matches: {{match_count}}"), &grouped_item()).unwrap(),
            "matches: 2"
        );
    }

    #[test]
    fn test_render_title_prefers_template_over_title() {
        assert_eq!(
            render_title(Some("fallback"), Some("{{filename}}"), &grouped_item()).unwrap(),
            "a.rb"
        );
    }

    #[test]
    fn test_render_title_uses_literal_title() {
        assert_eq!(
            render_title(Some("explicit title"), None, &grouped_item()).unwrap(),
            "explicit title"
        );
    }

    #[test]
    fn test_render_title_defaults_to_match_count_and_filepath() {
        assert_eq!(
            render_title(None, None, &grouped_item()).unwrap(),
            "2:lib/a.rb"
        );
    }
}
