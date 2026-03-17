import Foundation

struct GenreExplanation {
    let definition: String
    let hallmarks: String
    let historicalArc: String
    let analysisLens: String
}

final class GenreDefinitionService {
    static let shared = GenreDefinitionService()

    private let library: [String: GenreExplanation] = [
        "science-fiction": GenreExplanation(
            definition: "Science fiction explores speculative worlds built from scientific or technological change, then asks what that change does to people, institutions, and morality.",
            hallmarks: "Common markers include future or alternate societies, advanced technology, first-contact scenarios, dystopian governance, space exploration, and philosophical pressure-tests of identity and agency.",
            historicalArc: "The genre consolidated in late 19th and early 20th century prose, expanded through mid-century pulp and magazine culture, then surged globally in film and prestige TV as visual effects and digital culture matured.",
            analysisLens: "Expert reading focuses on what the story is really modeling: power systems, labor, surveillance, ecological futures, post-human identity, and whether progress is framed as liberation or control."
        ),
        "fantasy": GenreExplanation(
            definition: "Fantasy centers on worlds where the supernatural is foundational, using mythic structures to examine belief, destiny, and the ethics of power.",
            hallmarks: "Frequent elements include invented cosmologies, magical systems, quests, chosen-one narratives, political kingdoms, and symbolic creatures or artifacts.",
            historicalArc: "Its modern form grew from folklore and epic traditions, then gained mass popularity through 20th-century literary cycles and later franchise film/TV adaptations.",
            analysisLens: "Strong analysis tracks internal logic: what rules govern magic, who controls sacred knowledge, and how mythic stakes mirror real social anxieties."
        ),
        "horror": GenreExplanation(
            definition: "Horror is structured around fear, dread, and violation, using threat to expose social taboos and psychological fault lines.",
            hallmarks: "You typically see escalating uncertainty, body or space corruption, unstable perception, predatory forces, and moral transgression with consequence.",
            historicalArc: "From gothic literature to modern psychological and social horror, the genre repeatedly spikes in popularity during periods of broad cultural anxiety.",
            analysisLens: "Expert framing asks what the monster encodes: illness, class panic, gender violence, colonial guilt, technological fear, or collapse of institutional trust."
        ),
        "thriller": GenreExplanation(
            definition: "Thriller prioritizes sustained tension and high-stakes pursuit, organizing narrative momentum around risk, secrecy, and time pressure.",
            hallmarks: "Signature devices include unreliable allies, conspiracies, intelligence gaps, race-against-clock structures, and reveal reversals.",
            historicalArc: "It evolved from detective and espionage traditions into a dominant cross-medium form in late 20th-century cinema and serialized television.",
            analysisLens: "High-level critique examines information control: who knows what, when knowledge shifts power, and how suspense architecture governs audience alignment."
        ),
        "mystery": GenreExplanation(
            definition: "Mystery is an inquiry-driven genre where hidden causes are reconstructed through evidence, interpretation, and competing narratives.",
            hallmarks: "Expect clue chains, red herrings, witness unreliability, procedural routines, and final pattern disclosure.",
            historicalArc: "Popularized through serialized detective fiction, then institutionalized by crime publishing, radio, television procedurals, and prestige limited series.",
            analysisLens: "Expert analysis focuses on epistemology: what counts as evidence, how institutions gate truth, and how resolution reinforces or critiques order."
        ),
        "romance": GenreExplanation(
            definition: "Romance centers relational commitment as the primary arc, mapping emotional negotiation under social and personal constraints.",
            hallmarks: "Core conventions include attraction-friction-reconciliation beats, intimacy thresholds, competing commitments, and emotionally coded settings.",
            historicalArc: "A durable commercial engine in publishing for decades, with periodic visibility surges in film and streaming during shifts in audience segmentation.",
            analysisLens: "Serious reading examines consent dynamics, labor distribution in relationships, class/culture pressures, and what version of partnership is being legitimized."
        ),
        "drama": GenreExplanation(
            definition: "Drama emphasizes character consequence and moral conflict within realistic or near-realistic social frameworks.",
            hallmarks: "Typical traits are value collisions, interpersonal fallout, institutional pressure, and long-form character transformation.",
            historicalArc: "As a foundational narrative mode, drama persists across eras, but gains new popularity waves through prestige television and character-centric auteur cinema.",
            analysisLens: "Advanced critique tracks power gradients in dialogue and scene construction: who is allowed complexity, who absorbs consequence, and whose perspective is centered."
        ),
        "comedy": GenreExplanation(
            definition: "Comedy uses incongruity, timing, and social observation to produce laughter while renegotiating norms and status hierarchies.",
            hallmarks: "Common patterns include reversal, escalation, satire, absurdity, ensemble friction, and tonal pivots between sincerity and ridicule.",
            historicalArc: "It repeatedly reinvents with platform shifts, from stage and print to broadcast sitcoms, internet-native humor, and hybrid dramedy forms.",
            analysisLens: "Expert reading asks what the joke is doing structurally: diffusing tension, policing norms, attacking institutions, or enabling taboo discussion."
        )
    ]

    private init() {}

    func explanation(for genre: String, connectedItemCount: Int, topThemes: [String]) -> GenreExplanation {
        let normalized = normalize(genre)
        if let builtIn = library[normalized] {
            return builtIn
        }
        let leadThemes = topThemes.prefix(3).map { $0.replacingOccurrences(of: "-", with: " ") }.joined(separator: ", ")
        let themeLine = leadThemes.isEmpty ? "It currently has no dominant companion themes in this library view." : "Its strongest companion themes here are \(leadThemes)."
        return GenreExplanation(
            definition: "\(normalized.replacingOccurrences(of: "-", with: " ").capitalized) groups works that share stable narrative expectations, stylistic signals, and audience contracts.",
            hallmarks: "You usually see repeated story engines, familiar emotional beats, and recognizable world-building rules that make the genre legible quickly.",
            historicalArc: "Genre popularity tends to move in cycles driven by technology, distribution platforms, and cultural mood; this one currently maps to \(connectedItemCount) connected items in your graph.",
            analysisLens: "\(themeLine) A strong expert lens is to compare how those recurring expectations are either fulfilled, subverted, or hybridized across media."
        )
    }

    private func normalize(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^\p{L}\p{N}-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
