use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

use adblock::content_blocking::{ignore_previous_fp_documents, CbRule, CbRuleEquivalent};
use adblock::filters::cosmetic::{CosmeticFilterMask, CosmeticFilterOperator};
use adblock::lists::{parse_filters, ParseOptions, RuleTypes};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!("Usage: rule-converter <content_blocker_json> <cosmetic_filters_json> <input_file1> [input_file2 ...]");
        std::process::exit(1);
    }

    let cb_output_path = &args[1];
    let cosmetic_output_path = &args[2];
    let input_paths = &args[3..];

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
    opts.rule_types = RuleTypes::All;


    let (network_filters, cosmetic_filters) = parse_filters(all_lines.iter().map(|s| s.as_str()), true, opts);
    println!(
        "Parsed {} network filters and {} cosmetic filters in {:?}",
        network_filters.len(),
        cosmetic_filters.len(),
        parse_start.elapsed()
    );


    let convert_start = Instant::now();
    let mut cb_rules: Vec<CbRule> = Vec::new();
    for filter in network_filters {
        if let Ok(equiv) = CbRuleEquivalent::try_from(filter) {
            for rule in equiv {
                cb_rules.push(rule);
            }
        }
    }

    cb_rules.push(ignore_previous_fp_documents());
    println!("Converted to {} content blocking rules in {:?}", cb_rules.len(), convert_start.elapsed());


    let cosmetic_start = Instant::now();
    let mut domain_hide_map: HashMap<String, HashSet<String>> = HashMap::new();
    let mut domain_unhide_map: HashMap<String, HashSet<String>> = HashMap::new();

    for filter in &cosmetic_filters {
        let is_unhide = filter.mask.contains(CosmeticFilterMask::UNHIDE);
        let is_standard_hide = filter.mask.is_empty() && filter.action.is_none();

        if !is_unhide && !is_standard_hide {
            continue;
        }

        let mut selectors: Vec<String> = Vec::new();
        for op in &filter.selector {
            if let CosmeticFilterOperator::CssSelector(s) = op {
                let s_trimmed = s.trim();
                if !s_trimmed.is_empty() {
                    selectors.push(s_trimmed.to_string());
                }
            }
        }

        if selectors.is_empty() {
            continue;
        }

        if let Some(raw) = &filter.raw_line {
            let sep_pos = raw.find("#@#").or_else(|| raw.find("##")).or_else(|| raw.find("#?#"));
            if let Some(pos) = sep_pos {
                let domain_part = &raw[..pos];
                if !domain_part.is_empty() {
                    for d in domain_part.split(',') {
                        let d = d.trim().to_lowercase();
                        if !d.is_empty() && !d.starts_with('~') {
                            if is_unhide {
                                for s in &selectors {
                                    domain_unhide_map.entry(d.clone()).or_default().insert(s.clone());
                                }
                            } else {
                                for s in &selectors {
                                    domain_hide_map.entry(d.clone()).or_default().insert(s.clone());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    for (domain, unhide_set) in &domain_unhide_map {
        if let Some(hide_set) = domain_hide_map.get_mut(domain) {
            for sel in unhide_set {
                hide_set.remove(sel);
            }
        }
    }

    let mut compact_cosmetic_map: HashMap<String, String> = HashMap::new();
    let mut total_selectors_count = 0;
    for (domain, hide_set) in domain_hide_map {
        if !hide_set.is_empty() {
            total_selectors_count += hide_set.len();
            let mut sorted_selectors: Vec<String> = hide_set.into_iter().collect();
            sorted_selectors.sort();
            compact_cosmetic_map.insert(domain, sorted_selectors.join(",\n"));
        }
    }
    println!(
        "Extracted {} unique domain entries with {} total selectors in {:?}",
        compact_cosmetic_map.len(),
        total_selectors_count,
        cosmetic_start.elapsed()
    );

    let write_start = Instant::now();

    let cb_file = File::create(cb_output_path).unwrap_or_else(|e| {
        eprintln!("Error: Failed to create output file {}: {}", cb_output_path, e);
        std::process::exit(1);
    });
    let mut cb_writer = BufWriter::new(cb_file);
    serde_json::to_writer(&mut cb_writer, &cb_rules).unwrap_or_else(|e| {
        eprintln!("Error: Failed to serialize content blocker rules: {}", e);
        std::process::exit(1);
    });
    cb_writer.flush().unwrap_or_else(|e| {
        eprintln!("Error: Failed to flush {}: {}", cb_output_path, e);
        std::process::exit(1);
    });

    let cosmetic_file = File::create(cosmetic_output_path).unwrap_or_else(|e| {
        eprintln!("Error: Failed to create output file {}: {}", cosmetic_output_path, e);
        std::process::exit(1);
    });
    let mut cosmetic_writer = BufWriter::new(cosmetic_file);
    serde_json::to_writer(&mut cosmetic_writer, &compact_cosmetic_map).unwrap_or_else(|e| {
        eprintln!("Error: Failed to serialize cosmetic filters: {}", e);
        std::process::exit(1);
    });
    cosmetic_writer.flush().unwrap_or_else(|e| {
        eprintln!("Error: Failed to flush {}: {}", cosmetic_output_path, e);
        std::process::exit(1);
    });

    println!(
        "Wrote content blocker to {} and cosmetic filters to {} in {:?}",
        cb_output_path,
        cosmetic_output_path,
        write_start.elapsed()
    );
    println!("Rule conversion pipeline finished in {:?}", start.elapsed());
}
