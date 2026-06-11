"""Financial education catalogue.

Each topic ships with title + content in English / French / Cameroon
Pidgin, plus an `xaf_example` flag. When True the router renders the
example with amounts computed from the user's income bracket midpoint
at runtime, so the example feels personally calibrated rather than
generic.

Topics may declare `related_topics` so the Flutter education card can
render follow-up chips.
"""
from __future__ import annotations

from typing import Optional, TypedDict


class EducationTopic(TypedDict):
    title_en:        str
    title_fr:        str
    title_pidgin:    str
    content_en:      str
    content_fr:      str
    content_pidgin:  str
    xaf_example:     bool
    related_topics:  list[str]


# ─── Topics ────────────────────────────────────────────────────────

TOPICS: dict[str, EducationTopic] = {
    "savings_rate": {
        "title_en":     "Your savings rate",
        "title_fr":     "Votre taux d'épargne",
        "title_pidgin": "How much you dey save",
        "content_en":
            "Your savings rate is the share of your income you keep instead of spend. "
            "Aiming for 20% is a healthy benchmark — it leaves room for life while "
            "still building real cushion. Even 10% consistently beats 30% one good month "
            "and zero for the next two.",
        "content_fr":
            "Votre taux d'épargne, c'est la part de vos revenus que vous mettez de côté "
            "au lieu de dépenser. Viser 20% est un bon repère — vous gardez de quoi vivre "
            "tout en construisant un vrai filet de sécurité. Même 10% chaque mois bat 30% "
            "un mois et zéro les deux suivants.",
        "content_pidgin":
            "Savings rate na the part of your money wey you dey put aside instead of spend. "
            "Try reach 20% — e fit allow you live well while you still dey build "
            "small-small backup. Even 10% wey you do every month pass 30% wey you do "
            "only one month then zero for two months.",
        "xaf_example":    True,
        "related_topics": ["emergency_fund", "budget_building"],
    },
    "emergency_fund": {
        "title_en":     "Emergency fund",
        "title_fr":     "Fonds d'urgence",
        "title_pidgin": "Emergency money",
        "content_en":
            "An emergency fund is money you don't touch unless something genuinely "
            "unexpected happens — medical issue, urgent transport, sudden income loss. "
            "Aim for 3 months of essential expenses kept in a locked savings wallet you "
            "can reach in a day but not in five minutes. It's the difference between "
            "weathering a shock and borrowing at predatory rates.",
        "content_fr":
            "Un fonds d'urgence, c'est de l'argent que vous ne touchez pas sauf en cas "
            "d'imprévu réel — santé, transport urgent, perte de revenu. Visez 3 mois de "
            "dépenses essentielles, gardés dans un portefeuille verrouillé accessible en "
            "un jour mais pas en cinq minutes. C'est ce qui sépare encaisser un choc et "
            "emprunter à des taux ruineux.",
        "content_pidgin":
            "Emergency money na money wey you no go touch except true-true wahala happen — "
            "sickness, urgent transport, work problem. Target 3 months of your important "
            "spending, keep am for locked wallet wey you fit reach for one day but no fit "
            "reach for five minutes. E go save you from going borrow loan wey go suffer you.",
        "xaf_example":    True,
        "related_topics": ["savings_rate", "debt_vs_savings"],
    },
    "compound_interest": {
        "title_en":     "Compound interest",
        "title_fr":     "Les intérêts composés",
        "title_pidgin": "How money fit born money",
        "content_en":
            "Compound interest is the effect of earning interest on the interest you "
            "already earned. Small deposits left alone for long enough turn into amounts "
            "that look impossible from where you started. Time matters more than the "
            "amount you start with — the earliest XAF you save is worth far more than "
            "the same XAF saved years later.",
        "content_fr":
            "Les intérêts composés, c'est l'effet de gagner des intérêts sur les "
            "intérêts déjà gagnés. De petits dépôts laissés tranquilles assez longtemps "
            "deviennent des sommes qui paraissaient impossibles au départ. Le temps "
            "compte plus que la somme de départ — chaque XAF épargné tôt vaut bien plus "
            "que le même XAF épargné des années plus tard.",
        "content_pidgin":
            "Compound interest na when the small interest wey your money don dey collect "
            "self begin collect interest. Small deposit wey you leave for long time go turn "
            "big money wey you no fit believe. Time pass amount — XAF wey you save now pass "
            "the same XAF wey you go save next year.",
        "xaf_example":    True,
        "related_topics": ["savings_rate", "investment_basics"],
    },
    "budget_building": {
        "title_en":     "How to build a budget",
        "title_fr":     "Construire un budget",
        "title_pidgin": "How to plan your money",
        "content_en":
            "Start with one month of real numbers — write down every XAF that came in and "
            "every XAF that went out. Then group it: needs, wants, savings, "
            "obligations (Njangi, rent). A simple split is 50% needs / 30% wants / 20% "
            "savings, but adjust to your reality. The point isn't the perfect split — "
            "it's having the conversation with yourself.",
        "content_fr":
            "Commencez par un mois de vrais chiffres — notez chaque XAF entré et chaque "
            "XAF sorti. Regroupez ensuite : besoins, envies, épargne, obligations "
            "(Njangi, loyer). Une répartition simple : 50% besoins / 30% envies / 20% "
            "épargne, à adapter à votre situation. L'objectif n'est pas la répartition "
            "parfaite — c'est d'avoir la conversation avec vous-même.",
        "content_pidgin":
            "Start with one month of real numbers — write down every XAF wey enter and "
            "every XAF wey waka. Then group am: needs, wants, savings, obligations "
            "(Njangi, rent). Simple split na 50% needs / 30% wants / 20% savings, but "
            "you fit adjust am for your own life. The main thing na the talk wey you "
            "dey hold with yourself.",
        "xaf_example":    True,
        "related_topics": ["savings_rate", "debt_vs_savings"],
    },
    "debt_vs_savings": {
        "title_en":     "Debt vs savings",
        "title_fr":     "Dette ou épargne ?",
        "title_pidgin": "Loan or savings — wetin first?",
        "content_en":
            "If your debt costs more in interest than your savings earn, kill the debt first. "
            "In Cameroon a typical predatory loan can charge 10%+ per month — no savings "
            "product matches that. The exception: keep a small emergency cushion (1 month "
            "of expenses) before attacking the debt, so a small shock doesn't force you "
            "to borrow again on top.",
        "content_fr":
            "Si votre dette coûte plus d'intérêts que votre épargne n'en rapporte, tuez "
            "la dette en premier. Au Cameroun, un prêt abusif courant peut coûter 10%+ "
            "par mois — aucun produit d'épargne n'égale ça. Exception : gardez un petit "
            "coussin d'urgence (1 mois de dépenses) avant d'attaquer la dette, pour "
            "qu'un petit choc ne vous force pas à emprunter encore par-dessus.",
        "content_pidgin":
            "If your loan dey charge interest pass wetin your savings dey gain, kill "
            "the loan first. For Cameroon, some bad loans dey charge 10%+ for one month "
            "— no savings fit beat that. But before you face the loan, keep small "
            "emergency money (one month of spending), so small wahala no go push you "
            "back into another loan.",
        "xaf_example":    True,
        "related_topics": ["emergency_fund", "budget_building"],
    },
    "njangi_payout_explained": {
        "title_en":     "How Njangi payouts work",
        "title_fr":     "Comment fonctionnent les tours de Njangi",
        "title_pidgin": "How Njangi tour dey work",
        "content_en":
            "A Njangi is a rotating savings group. Every member contributes the same fixed "
            "amount each cycle, and one member receives the full pot per cycle. Order is "
            "agreed at the start (random draw, vote, or rotation). The earlier your "
            "position, the more it's effectively a loan from the group; the later your "
            "position, the more it's a savings vehicle.",
        "content_fr":
            "Une Njangi est un groupe d'épargne tournante. Chaque membre verse la même "
            "somme fixe à chaque cycle, et un membre reçoit la totalité du pot par cycle. "
            "L'ordre est convenu au départ (tirage, vote ou rotation). Plus votre position "
            "est tôt, plus c'est en fait un prêt du groupe ; plus elle est tard, plus "
            "c'est un instrument d'épargne.",
        "content_pidgin":
            "Njangi na rotating savings group. Every member dey put the same fixed money "
            "for each round, and one person dey collect the whole money. Una go agree the "
            "order from the start (draw, vote, or rotation). If you collect early, e be "
            "like loan; if you collect late, e be like savings.",
        "xaf_example":    True,
        "related_topics": ["savings_rate", "budget_building"],
    },
    "mobile_money_safety": {
        "title_en":     "Mobile Money safety",
        "title_fr":     "Sécurité Mobile Money",
        "title_pidgin": "How to keep your MoMo safe",
        "content_en":
            "Never share your MoMo PIN — not with an agent, not with anyone calling claiming "
            "to be MTN or Orange staff. Genuine MoMo support never asks for it. If you "
            "send to a wrong number, call your operator's official help line immediately; "
            "the faster you act, the higher the chance of recovery. Lock your phone with a "
            "PIN or biometric so the MoMo app isn't open to anyone who picks it up.",
        "content_fr":
            "Ne partagez jamais votre code MoMo — ni avec un agent, ni avec qui que ce soit "
            "qui appelle en se faisant passer pour MTN ou Orange. Le vrai support MoMo ne "
            "demande jamais ce code. Si vous envoyez à un mauvais numéro, appelez la ligne "
            "officielle de votre opérateur tout de suite ; plus vous agissez vite, plus "
            "vous avez de chances de récupérer. Verrouillez votre téléphone par code ou "
            "empreinte pour que l'app MoMo ne soit pas accessible à n'importe qui.",
        "content_pidgin":
            "Make you no share your MoMo PIN — no give am for agent, no give am for "
            "anybody wey call say na MTN or Orange. Real MoMo people no dey ever ask "
            "for am. If you send money go wrong number, call your operator official "
            "line one-time; the faster you call, the better. Lock your phone with PIN "
            "or fingerprint so MoMo app no go open for any person wey carry your phone.",
        "xaf_example":    False,
        "related_topics": ["budget_building"],
    },
    "investment_basics": {
        "title_en":     "Investment basics",
        "title_fr":     "Les bases de l'investissement",
        "title_pidgin": "Investment basics",
        "content_en":
            "Investing is buying something today that might be worth more tomorrow — stocks, "
            "a business, land, or a productive asset. It's not the same as saving. Saving "
            "preserves; investing grows. Rule of thumb: build a real emergency fund first, "
            "kill expensive debt, and only then start investing money you don't need for "
            "3+ years. Anyone selling 'guaranteed' high returns is selling a scam.",
        "content_fr":
            "Investir, c'est acheter aujourd'hui quelque chose qui pourrait valoir plus "
            "demain — actions, business, terrain, ou actif productif. Ce n'est pas la même "
            "chose qu'épargner. L'épargne préserve ; l'investissement fait croître. Règle "
            "simple : d'abord un vrai fonds d'urgence, ensuite tuer les dettes chères, "
            "et seulement ensuite investir l'argent dont vous n'aurez pas besoin avant "
            "3 ans. Toute personne vendant des 'rendements garantis' élevés vend une "
            "arnaque.",
        "content_pidgin":
            "Investment na when you buy something today wey go cost pass tomorrow — "
            "stocks, business, land, or any productive thing. Investment no be same "
            "as savings. Savings dey hold ya money safe; investment dey make am grow. "
            "Simple rule: first build emergency money, then finish bad loans, then "
            "you fit invest money wey you no go need for 3 years up. Any person wey "
            "promise 'guarantee' big returns dey try scam you.",
        "xaf_example":    True,
        "related_topics": ["emergency_fund", "compound_interest", "debt_vs_savings"],
    },
}


# ─── Helpers ───────────────────────────────────────────────────────

_LANGS = {"en", "fr", "pidgin"}


def get_topic(
    topic_key: str,
    *,
    language: str = "en",
    income_midpoint: Optional[int] = None,
) -> Optional[dict]:
    """Return a localised topic with an optional XAF-personalised example.

    The example block is computed here so the prompt builder + the Flutter
    education card can both display the same numbers.
    """
    topic = TOPICS.get(topic_key)
    if topic is None:
        return None
    lang = language if language in _LANGS else "en"
    title = topic[f"title_{lang}"]      # type: ignore[index]
    content = topic[f"content_{lang}"]  # type: ignore[index]

    example: Optional[str] = None
    if topic["xaf_example"] and income_midpoint:
        example = _xaf_example(topic_key, income_midpoint, lang)

    return {
        "topic_key":      topic_key,
        "title":          title,
        "content":        content,
        "language":       lang,
        "xaf_example":    example,
        "related_topics": topic["related_topics"],
    }


def _xaf_example(topic_key: str, midpoint: int, lang: str) -> str:
    """Compose the personalised example string for a topic."""
    twenty_pct = midpoint // 5            # 20% savings rate
    three_months_essential = midpoint * 2  # rough 2/3 essential * 3 months
    weekly = max(twenty_pct // 4, 1_000)

    if topic_key == "savings_rate":
        if lang == "fr":
            return (f"À votre niveau (~{midpoint:,} XAF/mois), un taux d'épargne de 20% "
                    f"vous met à {twenty_pct:,} XAF mis de côté chaque mois.")
        if lang == "pidgin":
            return (f"For your level (~{midpoint:,} XAF/month), 20% savings rate na "
                    f"{twenty_pct:,} XAF wey you go put aside every month.")
        return (f"At your level (~{midpoint:,} XAF/month), a 20% savings rate "
                f"means putting aside {twenty_pct:,} XAF every month.")

    if topic_key == "emergency_fund":
        if lang == "fr":
            return (f"Pour vous (~{midpoint:,} XAF/mois), visez environ "
                    f"{three_months_essential:,} XAF en fonds d'urgence.")
        if lang == "pidgin":
            return (f"For you (~{midpoint:,} XAF/month), target around "
                    f"{three_months_essential:,} XAF emergency money.")
        return (f"For you (~{midpoint:,} XAF/month), target roughly "
                f"{three_months_essential:,} XAF in your emergency fund.")

    if topic_key == "compound_interest":
        if lang == "fr":
            return (f"Si vous mettez de côté {weekly:,} XAF/semaine à 8% par an, "
                    f"vous aurez ~{int(weekly * 52 * 12 * 1.45):,} XAF après 10 ans.")
        if lang == "pidgin":
            return (f"If you save {weekly:,} XAF every week at 8% per year, "
                    f"after 10 years e go reach ~{int(weekly * 52 * 12 * 1.45):,} XAF.")
        return (f"If you set aside {weekly:,} XAF/week at 8% annual return, "
                f"after 10 years that's ~{int(weekly * 52 * 12 * 1.45):,} XAF.")

    if topic_key == "budget_building":
        needs = midpoint // 2
        wants = (midpoint * 30) // 100
        save  = midpoint // 5
        if lang == "fr":
            return (f"À ~{midpoint:,} XAF/mois : ~{needs:,} besoins, "
                    f"~{wants:,} envies, ~{save:,} épargne.")
        if lang == "pidgin":
            return (f"For ~{midpoint:,} XAF/month: ~{needs:,} needs, "
                    f"~{wants:,} wants, ~{save:,} savings.")
        return (f"At ~{midpoint:,} XAF/month: ~{needs:,} needs, "
                f"~{wants:,} wants, ~{save:,} savings.")

    if topic_key == "debt_vs_savings":
        cushion = midpoint
        if lang == "fr":
            return (f"Pour vous, gardez ~{cushion:,} XAF en filet d'urgence, "
                    f"puis dirigez tout l'excédent sur la dette.")
        if lang == "pidgin":
            return (f"For you, keep ~{cushion:,} XAF emergency money first, "
                    f"then put any extra money on top the loan.")
        return (f"For you, hold ~{cushion:,} XAF as your safety net, then "
                f"throw every extra XAF at the debt.")

    if topic_key == "njangi_payout_explained":
        contrib = twenty_pct // 2
        members = 10
        pot = contrib * members
        if lang == "fr":
            return (f"Avec un groupe de {members} et une cotisation de {contrib:,} XAF, "
                    f"le pot vaut {pot:,} XAF par cycle.")
        if lang == "pidgin":
            return (f"With group of {members} people and contribution of {contrib:,} XAF, "
                    f"the pot na {pot:,} XAF for one round.")
        return (f"With a {members}-member group at {contrib:,} XAF per contribution, "
                f"the pot is {pot:,} XAF each cycle.")

    if topic_key == "investment_basics":
        invest = max(weekly // 2, 500)
        if lang == "fr":
            return (f"À votre niveau, commencez petit — par ex. {invest:,} XAF/semaine "
                    f"sur un actif diversifié, après avoir bouclé fonds d'urgence et "
                    f"dette chère.")
        if lang == "pidgin":
            return (f"For your level, start small — like {invest:,} XAF every week for "
                    f"any diversified asset, after you don finish emergency money and "
                    f"bad loan.")
        return (f"At your level, start small — e.g. {invest:,} XAF/week into a "
                f"diversified asset, only after the emergency fund and high-cost debt "
                f"are sorted.")

    return ""
