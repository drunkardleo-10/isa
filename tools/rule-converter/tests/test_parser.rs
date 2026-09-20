use adblock::lists::{parse_filters, ParseOptions, RuleTypes};
use adblock::filters::cosmetic::CosmeticFilterMask;
use adblock::resources::{InMemoryResourceStorage, PermissionMask, Resource, ResourceStorage};
use std::fs::File;

#[test]
fn test_quick_fixes_rules() {
    let rules = vec![
    
        "m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com##+js(set, ytInitialPlayerResponse.playerAds, undefined)",
        "m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com##+js(set, ytInitialPlayerResponse.adPlacements, undefined)",
       
        "www.youtube.com##+js(json-prune-fetch-response, adPlacements adSlots playerResponse.adPlacements playerResponse.adSlots [].playerResponse.adPlacements [].playerResponse.adSlots, , propsToMatch, /player?)",
        "www.youtube.com##+js(json-prune-xhr-response, adPlacements adSlots playerResponse.adPlacements playerResponse.adSlots [].playerResponse.adPlacements [].playerResponse.adSlots, , propsToMatch, /\\/player(?:\\?.+)?$/)",
        "www.youtube.com##+js(set, ytcfg.data_.EXPERIMENT_FLAGS.all_web_enable_network_machine, false)",
    ];

    let mut opts = ParseOptions::default();
    opts.rule_types = RuleTypes::All;

    let (_, cosmetic) = parse_filters(rules.into_iter(), true, opts);
    assert_eq!(cosmetic.len(), 5, "All 5 rules should be parsed into cosmetic filters");

    let f = File::open("resources.json").expect("resources.json should exist");
    let resources: Vec<Resource> = serde_json::from_reader(f).expect("resources.json should parse");
    let storage = InMemoryResourceStorage::from_resources(resources);
    let res_storage = ResourceStorage::from_backend(storage);

    for (i, f) in cosmetic.iter().enumerate() {
        assert!(
            f.mask.contains(CosmeticFilterMask::SCRIPT_INJECT),
            "Rule {} must have SCRIPT_INJECT flag set",
            i
        );
        if let adblock::filters::cosmetic::CosmeticFilterOperator::CssSelector(args) = &f.selector[0] {
            let resolved = res_storage.get_scriptlet_resources(std::iter::once((args.as_str(), PermissionMask::from_bits(0xFF))));
            assert!(!resolved.is_empty(), "Rule {} should resolve to non-empty JS snippet", i);
            println!("Rule {} resolved successfully (len {})", i, resolved.len());
        }
    }
}
