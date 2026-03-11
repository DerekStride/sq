pub mod rg;

use anyhow::Result;

#[derive(Debug, Clone, PartialEq)]
pub enum Format {
    RgJson,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GroupedItem {
    pub filepath: String,
    pub text: String,
    pub match_count: usize,
}

pub fn detect_format(input: &str) -> Option<Format> {
    let first_line = input.lines().find(|line| !line.trim().is_empty())?;
    let value: serde_json::Value = serde_json::from_str(first_line).ok()?;
    match value.get("type").and_then(|v| v.as_str()) {
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
    if let Some(template) = title_template {
        let rendered = template
            .replace("{{filepath}}", &item.filepath)
            .replace("{{filename}}", filename_for(&item.filepath))
            .replace("{{match_count}}", &item.match_count.to_string());
        return Ok(rendered);
    }

    if let Some(title) = title {
        return Ok(title.to_string());
    }

    Ok(item.filepath.clone())
}
