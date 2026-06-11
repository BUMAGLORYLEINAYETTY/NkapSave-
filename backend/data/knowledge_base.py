"""NkapBot knowledge base — the corpus for semantic retrieval.

These are short, self-contained financial-literacy passages. At index-build
time each passage is embedded; at query time the user's question is embedded
and the closest passages are injected into Claude's prompt as grounding
KNOWLEDGE. This is the "documents" half of NkapBot's RAG — the other half is
the user's own live numbers (see nkapbot_context_service.py).

Two sources feed the corpus:
  1. The existing education catalogue (education_topics.TOPICS) — already
     written in English / French / Pidgin, so we reuse it verbatim.
  2. EXTRA_PASSAGES below — Cameroon-specific material the catalogue doesn't
     cover (Njangi default handling, MoMo fees & fraud, irregular income,
     inflation, banks vs Mobile Money).

Each chunk: {id, source, language, title, content, tags}. Languages are kept
as separate chunks so retrieval can prefer the user's language (with English
as a fallback pool).
"""
from __future__ import annotations

from typing import TypedDict

from data.education_topics import TOPICS


class KnowledgeChunk(TypedDict):
    id:       str
    source:   str        # "education" | "cameroon_guide"
    language: str        # "en" | "fr" | "pidgin"
    title:    str
    content:  str
    tags:     list[str]


# ─── Extra Cameroon-specific passages ──────────────────────────────
# (concept_key, tags) -> per-language {title, content}. Pidgin is optional;
# where omitted, English is used as the fallback pool for Pidgin queries.

EXTRA_PASSAGES: dict[str, dict] = {
    "njangi_default_handling": {
        "tags": ["njangi", "tontine", "default", "trust", "risk"],
        "en": {
            "title": "What happens when a Njangi member can't pay",
            "content":
                "In a Njangi, every member depends on every other member paying on time. "
                "If someone defaults, the group usually covers the gap from a penalty fund "
                "or splits the shortfall, and the defaulter's trust score drops — making it "
                "harder to join future cycles or claim an early position. Before you join, "
                "ask three things: who has already collected, what happens on a missed "
                "payment, and whether there is a written rule for removing a member. A group "
                "with clear default rules is far safer than one that relies on goodwill.",
        },
        "fr": {
            "title": "Que se passe-t-il quand un membre de Njangi ne peut pas payer",
            "content":
                "Dans une Njangi, chaque membre dépend du paiement ponctuel des autres. "
                "Si quelqu'un fait défaut, le groupe comble souvent le manque avec une "
                "caisse de pénalités ou répartit le déficit, et le score de confiance du "
                "défaillant baisse — ce qui complique l'accès aux cycles futurs ou à une "
                "position précoce. Avant d'adhérer, posez trois questions : qui a déjà "
                "encaissé, que se passe-t-il en cas d'impayé, et existe-t-il une règle "
                "écrite pour exclure un membre. Un groupe aux règles de défaut claires est "
                "bien plus sûr qu'un groupe qui repose sur la bonne foi.",
        },
    },
    "njangi_joining_safely": {
        "tags": ["njangi", "tontine", "join", "safety", "position"],
        "en": {
            "title": "How to join a Njangi safely",
            "content":
                "Treat a new Njangi like any financial commitment. Confirm the contribution "
                "amount, frequency, total number of members, and your payout position in "
                "writing before paying anything. An early position behaves like a loan from "
                "the group (you receive first, repay over the cycle); a late position behaves "
                "like disciplined savings. Only join groups where you know the organiser or "
                "have a trusted member vouching, and never contribute money you'll need "
                "before your payout cycle arrives.",
        },
        "fr": {
            "title": "Comment rejoindre une Njangi en toute sécurité",
            "content":
                "Considérez une nouvelle Njangi comme tout engagement financier. Confirmez "
                "par écrit le montant de la cotisation, la fréquence, le nombre total de "
                "membres et votre position de versement avant de payer quoi que ce soit. "
                "Une position précoce ressemble à un prêt du groupe (vous recevez en premier "
                "et remboursez sur le cycle) ; une position tardive ressemble à une épargne "
                "disciplinée. N'adhérez qu'à des groupes où vous connaissez l'organisateur "
                "ou un membre de confiance se porte garant, et ne cotisez jamais de l'argent "
                "dont vous aurez besoin avant l'arrivée de votre tour.",
        },
    },
    "momo_fees_awareness": {
        "tags": ["mobile money", "momo", "fees", "transfer", "withdrawal"],
        "en": {
            "title": "Mobile Money fees add up",
            "content":
                "Every Mobile Money send and withdrawal carries a fee, and those small "
                "charges quietly erode your balance over a month. Two habits cut the cost: "
                "batch withdrawals (take out one larger sum instead of many small ones) and "
                "keep money that's earmarked for savings inside a locked savings wallet "
                "rather than cashing it out and re-depositing. Before a transfer, check the "
                "fee shown — if it's a large share of a tiny amount, it may be cheaper to "
                "wait and combine transactions.",
        },
        "fr": {
            "title": "Les frais de Mobile Money s'accumulent",
            "content":
                "Chaque envoi et retrait Mobile Money entraîne des frais, et ces petites "
                "charges grignotent discrètement votre solde sur un mois. Deux habitudes "
                "réduisent le coût : regroupez vos retraits (retirez une somme plus "
                "importante au lieu de plusieurs petites) et gardez l'argent destiné à "
                "l'épargne dans un portefeuille verrouillé plutôt que de le retirer puis le "
                "redéposer. Avant un transfert, vérifiez les frais affichés — s'ils "
                "représentent une grande part d'un petit montant, mieux vaut attendre et "
                "combiner les transactions.",
        },
    },
    "momo_fraud_signals": {
        "tags": ["mobile money", "momo", "fraud", "scam", "safety", "pin"],
        "en": {
            "title": "Spotting Mobile Money fraud",
            "content":
                "Most Mobile Money fraud relies on tricking you, not breaking the system. "
                "Warning signs: a call or SMS claiming you 'received money by mistake' and "
                "asking you to send it back; anyone requesting your PIN or a one-time code; "
                "an 'agent' pushing you to confirm a transfer you didn't start; or a deal "
                "that needs an urgent deposit. Real operator staff never ask for your PIN. "
                "When in doubt, hang up and dial your operator's official short code "
                "yourself — never the number that contacted you.",
        },
        "fr": {
            "title": "Repérer la fraude Mobile Money",
            "content":
                "La plupart des fraudes Mobile Money reposent sur la tromperie, pas sur le "
                "piratage du système. Signaux d'alerte : un appel ou SMS prétendant que vous "
                "avez « reçu de l'argent par erreur » et vous demandant de le renvoyer ; "
                "quiconque réclame votre code PIN ou un code à usage unique ; un « agent » "
                "qui vous presse de confirmer un transfert que vous n'avez pas lancé ; ou une "
                "offre exigeant un dépôt urgent. Le vrai personnel de l'opérateur ne demande "
                "jamais votre PIN. En cas de doute, raccrochez et composez vous-même le code "
                "court officiel de votre opérateur — jamais le numéro qui vous a contacté.",
        },
    },
    "irregular_income": {
        "tags": ["irregular income", "budget", "smoothing", "informal", "savings"],
        "en": {
            "title": "Budgeting on an irregular income",
            "content":
                "If your income swings month to month — common with trade, farming, or gig "
                "work — budget from your low months, not your good ones. Work out the minimum "
                "you reliably earn and build your essential spending around that floor. In a "
                "strong month, move the surplus straight into savings before it gets spent, "
                "so it can carry you through a lean month. The goal is to smooth your "
                "spending even when your income won't.",
        },
        "fr": {
            "title": "Budgétiser avec un revenu irrégulier",
            "content":
                "Si votre revenu varie d'un mois à l'autre — fréquent dans le commerce, "
                "l'agriculture ou les petits boulots — budgétisez à partir de vos mois "
                "faibles, pas de vos bons mois. Déterminez le minimum que vous gagnez de "
                "façon fiable et bâtissez vos dépenses essentielles autour de ce plancher. "
                "Lors d'un bon mois, placez le surplus directement dans l'épargne avant qu'il "
                "ne soit dépensé, afin qu'il vous porte pendant un mois maigre. L'objectif "
                "est de lisser vos dépenses même quand votre revenu ne le fait pas.",
        },
    },
    "inflation_basics": {
        "tags": ["inflation", "prices", "purchasing power", "savings"],
        "en": {
            "title": "Why money loses value over time",
            "content":
                "Inflation means prices rise, so the same XAF buys a little less each year. "
                "Cash kept idle slowly loses purchasing power even though the number doesn't "
                "change. This is why a savings goal with a deadline far in the future should "
                "aim a bit higher than today's price, and why money you won't need for years "
                "is better placed in something that at least keeps pace with prices rather "
                "than sitting still. It is not a reason to rush into risky 'high-return' "
                "schemes.",
        },
        "fr": {
            "title": "Pourquoi l'argent perd de la valeur avec le temps",
            "content":
                "L'inflation signifie que les prix montent : le même XAF achète un peu moins "
                "chaque année. L'argent laissé inactif perd lentement son pouvoir d'achat "
                "même si le chiffre ne change pas. C'est pourquoi un objectif d'épargne dont "
                "l'échéance est lointaine devrait viser un peu plus haut que le prix "
                "d'aujourd'hui, et pourquoi l'argent dont vous n'aurez pas besoin avant des "
                "années est mieux placé dans quelque chose qui suit au moins les prix plutôt "
                "que de rester immobile. Ce n'est pas une raison pour se précipiter sur des "
                "montages risqués à « haut rendement ».",
        },
    },
    "bank_vs_momo": {
        "tags": ["bank", "mobile money", "momo", "savings", "account"],
        "en": {
            "title": "Bank account vs Mobile Money for savings",
            "content":
                "Mobile Money is excellent for everyday payments and reaching people fast, "
                "but its convenience also makes it easy to spend. A separate bank or locked "
                "savings wallet adds a small amount of friction — exactly what savings need. "
                "A practical setup: keep spending money in Mobile Money, and move savings "
                "into an account you don't carry on your phone's home screen. The harder it "
                "is to dip into, the more likely the goal survives.",
        },
        "fr": {
            "title": "Compte bancaire ou Mobile Money pour épargner",
            "content":
                "Le Mobile Money est excellent pour les paiements quotidiens et pour "
                "atteindre les gens rapidement, mais sa commodité le rend aussi facile à "
                "dépenser. Un compte bancaire séparé ou un portefeuille d'épargne verrouillé "
                "ajoute un peu de friction — exactement ce dont l'épargne a besoin. Une "
                "configuration pratique : gardez l'argent de dépense sur Mobile Money et "
                "déplacez l'épargne vers un compte que vous n'avez pas sur l'écran d'accueil "
                "de votre téléphone. Plus il est difficile d'y toucher, plus l'objectif a de "
                "chances de tenir.",
        },
    },
}


# ─── Corpus assembly ───────────────────────────────────────────────

_CATALOGUE_LANGS = ("en", "fr", "pidgin")


def build_corpus() -> list[KnowledgeChunk]:
    """Flatten the education catalogue + extra passages into one list of
    per-language chunks ready for embedding."""
    chunks: list[KnowledgeChunk] = []

    # 1. Education catalogue (already localised in 3 languages).
    for key, topic in TOPICS.items():
        for lang in _CATALOGUE_LANGS:
            chunks.append(KnowledgeChunk(
                id=f"education:{key}:{lang}",
                source="education",
                language=lang,
                title=topic[f"title_{lang}"],      # type: ignore[literal-required]
                content=topic[f"content_{lang}"],  # type: ignore[literal-required]
                tags=list(topic.get("related_topics", [])) + [key],
            ))

    # 2. Extra Cameroon-specific passages (en / fr; Pidgin falls back to en).
    for key, spec in EXTRA_PASSAGES.items():
        tags = list(spec.get("tags", []))
        for lang in ("en", "fr"):
            loc = spec.get(lang)
            if not loc:
                continue
            chunks.append(KnowledgeChunk(
                id=f"cameroon_guide:{key}:{lang}",
                source="cameroon_guide",
                language=lang,
                title=loc["title"],
                content=loc["content"],
                tags=tags,
            ))

    return chunks


def corpus_text(chunk: KnowledgeChunk) -> str:
    """The exact text that gets embedded for a chunk — title + content so the
    heading's keywords contribute to the match."""
    return f"{chunk['title']}\n{chunk['content']}"
