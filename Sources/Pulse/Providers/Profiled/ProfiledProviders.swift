// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Provider {
    /// The profile of a provider written as one, or nil for the ones that
    /// answer every switch themselves. One line per provider; the profile
    /// itself is in that provider's own file beside this one.
    var profile: ProviderProfile? {
        switch self {
        case .clinePass: .clinePass
        case .alibabaCodingPlan: .alibabaCodingPlan
        case .alibabaTokenPlan: .alibabaTokenPlan
        case .qwenCloud: .qwenCloud
        case .factory: .factory
        case .gemini: .gemini
        case .kiloCode: .kiloCode
        case .augment: .augment
        case .jetBrainsAI: .jetBrainsAI
        case .t3Chat: .t3Chat
        case .synthetic: .synthetic
        case .elevenLabs: .elevenLabs
        case .warp: .warp
        case .windsurf: .windsurf
        case .bifrost: .bifrost
        case .chutes: .chutes
        case .longCat: .longCat
        case .zoomMate: .zoomMate
        case .notionAI: .notionAI
        case .ibmBob: .ibmBob
        case .nousPortal: .nousPortal
        case .raycastAI: .raycastAI
        case .gitKraken: .gitKraken
        case .xKiro: .xKiro
        case .abacus: .abacus
        case .moonshot: .moonshot
        case .hyper: .hyper
        case .atlasCloud: .atlasCloud
        case .poe: .poe
        case .venice: .venice
        case .openAIPlatform: .openAIPlatform
        case .amp: .amp
        case .zed: .zed
        case .sakana: .sakana
        case .mistral: .mistral
        case .codebuff: .codebuff
        case .llmProxy: .llmProxy
        case .liteLLM: .liteLLM
        case .aixy: .aixy
        case .neuralwatt: .neuralwatt
        case .clawRouter: .clawRouter
        case .zenMux: .zenMux
        case .v0: .v0
        case .devPass: .devPass
        case .perplexity: .perplexity
        case .manus: .manus
        case .huggingFace: .huggingFace
        case .deepInfra: .deepInfra
        case .xaiAPI: .xaiAPI
        case .replicate: .replicate
        case .typeSafe: .typeSafe
        case .vercelAIGateway: .vercelAIGateway
        default: nil
        }
    }
}
