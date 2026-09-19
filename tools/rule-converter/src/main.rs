use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

use adblock::content_blocking::{ignore_previous_fp_documents, CbRule, CbRuleEquivalent};
use adblock::lists::{parse_filters, ParseOptions, RuleTypes};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: rule-converter <output_json> <input_file1> [input_file2 ...]");
        std::process::exit(1);
    }

    let output_path = &args[1];
    let input_paths = &args[2..];

    let start = Instant::now();
    let mut all_lines = Vec::new();
    for path in input_paths {
        let f = File::open(path).unwrap_or_else(|e| {
            eprintln!("Error: Failed to open input file {}: {}", path, e);
            std::process::exit(1);
        });
        let reader = BufReader::new(f);
        for line in reader.lines() {
            if let Ok(l) = line {
                let trimmed = l.trim();
                if !trimmed.is_empty() && !trimmed.starts_with('!') && !trimmed.starts_with('[') {
                    all_lines.push(l);
                }
            }
        }
    }
    println!("Loaded {} raw filter rules in {:?}", all_lines.len(), start.elapsed());

    let parse_start = Instant::now();
    let mut opts = ParseOptions::default();
    opts.rule_types = RuleTypes::NetworkOnly;

    // debug=true is required so that raw_line is retained for CbRuleEquivalent conversion
    let (network_filters, _) = parse_filters(all_lines.iter().map(|s| s.as_str()), true, opts);
    println!("Parsed {} network filters in {:?}", network_filters.len(), parse_start.elapsed());

    let convert_start = Instant::now();
    let mut cb_rules: Vec<CbRule> = Vec::new();
    for filter in network_filters {
        if let Ok(equiv) = CbRuleEquivalent::try_from(filter) {
            for rule in equiv {
                cb_rules.push(rule);
            }
        }
    }
    // Approximates default ABP behavior: do not block top-level first-party documents
    cb_rules.push(ignore_previous_fp_documents());
    println!("Converted to {} content blocking rules in {:?}", cb_rules.len(), convert_start.elapsed());

    let write_start = Instant::now();
    let out_file = File::create(output_path).unwrap_or_else(|e| {
        eprintln!("Error: Failed to create output file {}: {}", output_path, e);
        std::process::exit(1);
    });
    let mut writer = BufWriter::new(out_file);
    serde_json::to_writer(&mut writer, &cb_rules).unwrap_or_else(|e| {
        eprintln!("Error: Failed to serialize rules to JSON: {}", e);
        std::process::exit(1);
    });
    writer.flush().unwrap_or_else(|e| {
        eprintln!("Error: Failed to flush output file: {}", e);
        std::process::exit(1);
    });
    println!("Wrote content blocker JSON to {} in {:?}", output_path, write_start.elapsed());
    println!("Rule conversion completed in {:?}", start.elapsed());
}
