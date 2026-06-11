"""Prompt builder for the NkapBot Claude calls.

Produces the system prompt that's sent to claude-sonnet-4 for every
NkapBot request. The prompt:
  * is selected by language (en / fr / pidgin)
  * injects the user's identity, city, income bracket, selected features
  * embeds the retrieved RAG context as readable structured text
  * enforces the behavioural rules (XAF only, advisory only, etc.)

Public API: build_system_prompt(context, category, enabled_features, topic=None)
"""
from __future__ import annotations

import json
from typing import Optional


# ─── Language templates ────────────────────────────────────────────
#
# Each template uses {placeholders} that are filled in below. Keep them
# parallel so the same placeholders mean the same thing across languages.

_RULES_BLOCK_EN = """\
RULES (always follow):
1. Reply in English. Never switch language unless the user explicitly asks.
2. All money amounts are in XAF (Central African CFA franc). Never USD, EUR, or %.
3. You ADVISE only. You NEVER move money, execute transactions, or take action
   on the user's behalf — the user always acts themselves.
4. Stay strictly within personal finance for Cameroon (savings, expenses,
   budgeting, Njangi/tontine, Mobile Money safety, debt, basic investing).
5. Reference the user's actual numbers from CONTEXT in every answer. If a
   number isn't in CONTEXT, say "I don't have that yet" rather than guess.
6. Be warm, direct, and practical. Short sentences. No fluff.
7. For education questions, end with one short Cameroonian example using
   XAF figures sized to the user's income bracket.
"""

_RULES_BLOCK_FR = """\
RÈGLES (toujours suivies) :
1. Répondez en français. Ne changez de langue que si l'utilisateur le demande.
2. Toutes les sommes sont en XAF (franc CFA). Jamais USD, EUR, ni %.
3. Vous CONSEILLEZ uniquement. Vous ne déplacez JAMAIS d'argent, n'exécutez
   PAS de transactions, ne faites RIEN au nom de l'utilisateur — c'est lui
   qui agit toujours.
4. Restez strictement dans la finance personnelle au Cameroun (épargne,
   dépenses, budget, Njangi/tontine, sécurité Mobile Money, dette,
   investissement de base).
5. Citez les vrais chiffres de l'utilisateur depuis CONTEXTE dans chaque
   réponse. Si une donnée manque, dites « je ne l'ai pas encore » plutôt
   que d'inventer.
6. Soyez chaleureux, direct et pratique. Phrases courtes. Pas de remplissage.
7. Pour les questions éducatives, terminez par un court exemple camerounais
   avec des montants XAF calibrés sur la tranche de revenu de l'utilisateur.
"""

_RULES_BLOCK_PIDGIN = """\
RULES (always follow):
1. Reply for Cameroon Pidgin. No change language except user ask.
2. Every money figure na for XAF (CFA franc). No USD, no EUR, no %.
3. You dey ADVISE only. You no go ever move money, do transaction, or take
   action for the user — na the user dey act for himself.
4. Stay only inside personal finance for Cameroon (savings, spending,
   budget, Njangi/tontine, MoMo safety, loan, basic investment).
5. Use the user real numbers from CONTEXT for every answer. If you no
   get the number, just talk "I no get am yet", no go invent.
6. Be warm, direct, and practical. Short sentence. No long talk.
7. For education question, end with one short Cameroon example using
   XAF amount wey match the user income bracket.
"""

_HEADER_EN = (
    "You are NkapBot — the personal finance assistant inside NkapSave, "
    "a Cameroonian savings app. You help {name}, who lives in {city}.\n\n"
    "User profile:\n"
    "- Income bracket: {income}\n"
    "- Preferred language: English\n"
    "- Active features: {features}\n\n"
    "Current question category: {category}\n"
)

_HEADER_FR = (
    "Vous êtes NkapBot — l'assistant de finance personnelle dans NkapSave, "
    "une appli d'épargne camerounaise. Vous aidez {name}, qui habite à {city}.\n\n"
    "Profil utilisateur :\n"
    "- Tranche de revenu : {income}\n"
    "- Langue préférée : Français\n"
    "- Fonctionnalités actives : {features}\n\n"
    "Catégorie de la question actuelle : {category}\n"
)

_HEADER_PIDGIN = (
    "You be NkapBot — the personal finance helper inside NkapSave, "
    "one Cameroon savings app. You dey help {name}, wey live for {city}.\n\n"
    "User profile:\n"
    "- Income bracket: {income}\n"
    "- Preferred language: Cameroon Pidgin\n"
    "- Active features: {features}\n\n"
    "Current question category: {category}\n"
)


# ─── Public entry ──────────────────────────────────────────────────

def build_system_prompt(
    context: dict,
    category: str,
    enabled_features: Optional[list[str]] = None,
    topic: Optional[dict] = None,
) -> str:
    """Compose the full system prompt for one Claude call."""
    user = context.get("user") or {}
    lang = (user.get("preferred_language") or "en").lower()

    name     = user.get("full_name") or "the user"
    city     = user.get("city") or "Cameroon"
    bracket  = user.get("income_bracket") or "not set"
    midpoint = user.get("income_midpoint")
    income_str = bracket if not midpoint else f"{bracket} (~{midpoint:,} XAF/month midpoint)"

    feats = ", ".join(enabled_features) if enabled_features else "all"

    if lang == "fr":
        header = _HEADER_FR
        rules  = _RULES_BLOCK_FR
        context_label = "CONTEXTE"
        topic_label   = "SUJET ÉDUCATIF"
    elif lang in ("pidgin", "pcm"):
        header = _HEADER_PIDGIN
        rules  = _RULES_BLOCK_PIDGIN
        context_label = "CONTEXT"
        topic_label   = "EDUCATION TOPIC"
    else:
        header = _HEADER_EN
        rules  = _RULES_BLOCK_EN
        context_label = "CONTEXT"
        topic_label   = "EDUCATION TOPIC"

    header = header.format(
        name=name, city=city, income=income_str,
        features=feats, category=category,
    )

    context_block = _render_context(context, category)
    parts = [header, rules, f"{context_label}:\n{context_block}"]

    # Semantically-retrieved reference passages (NkapBot's knowledge base).
    knowledge = context.get("knowledge") or []
    if knowledge:
        if lang == "fr":
            kb_label = "BASE DE CONNAISSANCES"
            kb_note = ("Référez-vous à ces passages pour expliquer les concepts. "
                       "Reformulez-les avec vos mots et les chiffres de l'utilisateur ; "
                       "ne les citez pas mot pour mot et n'inventez rien au-delà.")
        elif lang in ("pidgin", "pcm"):
            kb_label = "KNOWLEDGE BASE"
            kb_note = ("Use these passages to explain the concept. Put am for your own "
                       "words with the user numbers; no copy am word-for-word, no add "
                       "thing wey no dey there.")
        else:
            kb_label = "KNOWLEDGE BASE"
            kb_note = ("Use these passages to explain concepts. Put them in your own "
                       "words alongside the user's numbers; don't quote them verbatim "
                       "and don't invent facts beyond them.")
        parts.append(f"{kb_label} ({kb_note}):\n{_render_knowledge(knowledge)}")

    if topic is not None:
        parts.append(f"{topic_label}:\n{_render_topic(topic)}")

    return "\n\n".join(parts).strip()


# ─── Internals ─────────────────────────────────────────────────────

def _render_context(context: dict, category: str) -> str:
    """Render the retrieved context as readable structured text rather
    than raw JSON. Cheaper tokens and easier for Claude to scan."""
    out: list[str] = []

    if category in ("expenses", "health"):
        exp = context.get("expenses") or {}
        if exp:
            out.append("EXPENSES (this month):")
            out.append(f"  - Total this month: {exp.get('month_total', 0):,} XAF")
            out.append(f"  - Total previous month: {exp.get('prev_month_total', 0):,} XAF")
            by_cat = exp.get("by_category") or {}
            if by_cat:
                out.append("  - By category:")
                for c, amt in sorted(by_cat.items(), key=lambda kv: -kv[1]):
                    out.append(f"      {c}: {amt:,} XAF")
            budgets = exp.get("budgets") or {}
            if budgets:
                out.append("  - Monthly budgets:")
                for c, lim in budgets.items():
                    spent = by_cat.get(c, 0)
                    status = "OVER" if spent > lim else "ok"
                    out.append(f"      {c}: {spent:,}/{lim:,} XAF ({status})")
            recent = exp.get("recent_transactions") or []
            if recent:
                out.append(f"  - Recent transactions ({min(len(recent), 5)} of {len(recent)}):")
                for r in recent[:5]:
                    out.append(f"      {r['date'] or '?'} · {r['name']} · "
                               f"{r['category']} · {r['amount']:,} XAF")

    if category in ("savings", "health"):
        sav = context.get("savings") or {}
        if sav:
            out.append("SAVINGS:")
            goals = sav.get("goals") or []
            if goals:
                out.append(f"  - Goals ({len(goals)}):")
                for g in goals:
                    out.append(f"      {g.get('emoji', '🎯')} {g['name']}: "
                               f"{g['current']:,} / {g['target']:,} XAF · "
                               f"deadline {g.get('deadline') or 'none'} · "
                               f"{'done' if g['is_completed'] else 'active'}")
            plans = sav.get("plans") or []
            if plans:
                out.append(f"  - Auto-save plans ({len(plans)}):")
                for p in plans:
                    out.append(f"      {p['amount']:,} XAF / {p['frequency']} · "
                               f"active={p['active']} · "
                               f"reminders={p.get('reminder_enabled', True)}")
            as30 = sav.get("auto_save_30d") or {}
            if as30:
                out.append(f"  - Auto-save 30-day: "
                           f"{as30.get('successes', 0)}/{as30.get('attempts', 0)} succeeded")

    if category in ("njangi", "health"):
        nj = context.get("njangi") or {}
        if nj:
            out.append("NJANGI:")
            out.append(f"  - Groups: {nj.get('group_count', 0)}")
            if nj.get("avg_trust") is not None:
                out.append(f"  - Average trust score: {nj['avg_trust']}")
            for g in (nj.get("groups") or [])[:5]:
                out.append(f"      {g['name']}: contribution {g['contribution']:,} XAF "
                           f"({g['frequency']}), cycle {g['current_cycle']}/{g['total_cycles']}, "
                           f"trust {g['trust_score']}")

    if category == "education":
        edu = context.get("education") or {}
        if edu.get("income_midpoint"):
            out.append(f"For XAF examples: scale around ~{edu['income_midpoint']:,} XAF/month "
                       f"({edu.get('income_bracket')}).")

    # Health-specific computed block — injected by the router after calling
    # financial_health_service if present.
    if "health" in context:
        h = context["health"]
        out.append("HEALTH SCORE:")
        out.append(f"  - Overall: {h['overall_score']}/100 ({h['rating']})")
        for c in h["components"]:
            out.append(f"      [{int(c['weight']*100)}%] {c['key']}: "
                       f"{c['score']}/100 — {c['explanation']}")
        out.append(f"  - Top tip: {h['top_improvement_tip']}")

    # Spending patterns block.
    patterns = context.get("patterns") or []
    if patterns:
        out.append("SPENDING PATTERNS:")
        for p in patterns:
            out.append(f"  - [{p['severity']}] {p['pattern_type']}: {p['description']} "
                       f"→ {p['suggestion']}")

    if not out:
        # Fall back to a brief JSON dump so we never send an empty context.
        return json.dumps(context, indent=2, default=str)
    return "\n".join(out)


def _render_knowledge(knowledge: list[dict]) -> str:
    """Render retrieved knowledge-base passages as a compact numbered list."""
    lines: list[str] = []
    for i, hit in enumerate(knowledge, start=1):
        lines.append(f"[{i}] {hit['title']}")
        lines.append(f"    {hit['content']}")
    return "\n".join(lines)


def _render_topic(topic: dict) -> str:
    lines = [f"Title: {topic['title']}", topic["content"]]
    if topic.get("xaf_example"):
        lines.append("")
        lines.append(f"Example for this user: {topic['xaf_example']}")
    if topic.get("related_topics"):
        lines.append(f"Related: {', '.join(topic['related_topics'])}")
    return "\n".join(lines)
