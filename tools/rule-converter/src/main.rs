use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

use adblock::content_blocking::{ignore_previous_fp_documents, CbRule, CbRuleEquivalent};
use adblock::filters::cosmetic::{CosmeticFilterMask, CosmeticFilterOperator};
use adblock::lists::{parse_filters, ParseOptions, RuleTypes};
use adblock::resources::{InMemoryResourceStorage, PermissionMask, Resource, ResourceStorage};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 6 {
        eprintln!(
            "Usage: rule-converter <content_blocker_json> <cosmetic_filters_json> <scriptlets_json> <resources_json> <input_file1> [input_file2 ...]"
        );
        std::process::exit(1);
    }

    let cb_output_path = &args[1];
    let cosmetic_output_path = &args[2];
    let scriptlets_output_path = &args[3];
    let resources_path = &args[4];
    let input_paths = &args[5..];

    let start = Instant::now();

    let res_file = File::open(resources_path).unwrap_or_else(|e| {
        eprintln!("Error: Failed to open resources file {}: {}", resources_path, e);
        std::process::exit(1);
    });
    let resources: Vec<Resource> = serde_json::from_reader(BufReader::new(res_file)).unwrap_or_else(|e| {
        eprintln!("Error: Failed to deserialize resources JSON from {}: {}", resources_path, e);
        std::process::exit(1);
    });
    println!("Loaded {} resources in {:?}", resources.len(), start.elapsed());
    let storage = InMemoryResourceStorage::from_resources(resources);
    let res_storage = ResourceStorage::from_backend(storage);

    let load_start = Instant::now();
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
    println!("Loaded {} raw filter rules in {:?}", all_lines.len(), load_start.elapsed());

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

    let mut domain_scriptlets_map: HashMap<String, Vec<String>> = HashMap::new();
    let mut seen_scriptlets_by_domain: HashMap<String, HashSet<String>> = HashMap::new();

    for filter in &cosmetic_filters {
        let is_unhide = filter.mask.contains(CosmeticFilterMask::UNHIDE);
        let is_scriptlet = filter.mask.contains(CosmeticFilterMask::SCRIPT_INJECT);
        let is_standard_hide = filter.mask.is_empty() && filter.action.is_none();

        if is_scriptlet {
            if let Some(raw) = &filter.raw_line {
                let sep_pos = raw.find("##+js(").or_else(|| raw.find("#@#+js("));
                if let Some(pos) = sep_pos {
                    let domain_part = &raw[..pos];
                    if !domain_part.is_empty() {
                        let mut domains = Vec::new();
                        for d in domain_part.split(',') {
                            let d = d.trim().to_lowercase();
                            if !d.is_empty() && !d.starts_with('~') {
                                domains.push(d);
                            }
                        }

                        let is_yt = domains.iter().any(|d| d == "youtube.com" || d.ends_with(".youtube.com"));
                        if is_yt {
                            for op in &filter.selector {
                                if let CosmeticFilterOperator::CssSelector(args) = op {
                                    let resolved = res_storage.get_scriptlet_resources(std::iter::once((
                                        args.as_str(),
                                        PermissionMask::from_bits(0xFF),
                                    )));

                                    if !resolved.is_empty() {

                                        let mut target_domains = domains.clone();
                                        if !target_domains.iter().any(|d| d == "youtube.com") {
                                            target_domains.push("youtube.com".to_string());
                                        }

                                        for d in target_domains {
                                            if d == "youtube.com" || d.ends_with(".youtube.com") {
                                                let seen = seen_scriptlets_by_domain.entry(d.clone()).or_default();
                                                if seen.insert(resolved.clone()) {
                                                    domain_scriptlets_map.entry(d).or_default().push(resolved.clone());
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            continue;
        }

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

    let mut total_scriptlet_snippets = 0;
    for (domain, snippets) in &domain_scriptlets_map {
        total_scriptlet_snippets += snippets.len();
        println!("Domain '{}' has {} resolved scriptlet snippets", domain, snippets.len());
    }
    println!("Extracted {} domain scriptlet entries with {} snippets", domain_scriptlets_map.len(), total_scriptlet_snippets);

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

    let scriptlets_file = File::create(scriptlets_output_path).unwrap_or_else(|e| {
        eprintln!("Error: Failed to create output file {}: {}", scriptlets_output_path, e);
        std::process::exit(1);
    });
    let mut scriptlets_writer = BufWriter::new(scriptlets_file);
    serde_json::to_writer(&mut scriptlets_writer, &domain_scriptlets_map).unwrap_or_else(|e| {
        eprintln!("Error: Failed to serialize scriptlets: {}", e);
        std::process::exit(1);
    });
    scriptlets_writer.flush().unwrap_or_else(|e| {
        eprintln!("Error: Failed to flush {}: {}", scriptlets_output_path, e);
        std::process::exit(1);
    });

    println!(
        "Wrote content blocker to {}, cosmetic filters to {}, scriptlets to {} in {:?}",
        cb_output_path,
        cosmetic_output_path,
        scriptlets_output_path,
        write_start.elapsed()
    );
    println!("Rule conversion pipeline finished in {:?}", start.elapsed());
}
