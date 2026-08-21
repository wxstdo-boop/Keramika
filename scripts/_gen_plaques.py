# -*- coding: utf-8 -*-
"""Generate 80 new _PerfPlaque entries (21..100) and en/ru/fr translations."""
import io, os, sys

# (title_en, short_en, full_en, title_ru, short_ru, full_ru, title_fr, short_fr, full_fr)
# full texts use \n as line separator -> dart uses '\n' escapes
CARDS = [
# 21
("Comparison", "Your journey is not their highlight reel.", "Comparing your insides to others’ outsides is unfair.\nThey show highlights; you live with outtakes.\nRun your own race at your own pace.\nYour finish line is not theirs.",
 "Сравнение", "Твой путь — не их лента успеха.", "Сравнивать свои внутренности с чужими обложками нечестно.\nОни показывают лучшее; ты живёшь с дублями.\nБеги свою дистанцию в своём темпе.\nТвой финиш — не их.",
 "Comparaison", "Ton parcours n’est pas leur fil de réussite.", "Comparer ton intérieur aux photos des autres est injuste.\nIls montrent le meilleur ; tu vis avec les ratés.\nCours ta propre course à ton rythme.\nTa ligne d’arrivée n’est pas la leur."),
# 22
("Waiting for the right moment", "The right moment is the one you make.", "You are waiting for conditions that never arrive.\nStart now, adjust as you go.\nThe perfect moment is a myth that keeps you stuck.\nMake the moment right by moving.",
 "Ожидание правильного момента", "Правильный момент — тот, что ты создаёшь.", "Ты ждёшь условий, которые никогда не наступят.\nНачни сейчас, корректируй по ходу.\nИдеальный момент — миф, который держит в тупике.\nСделай момент правильным движением.",
 "Attendre le bon moment", "Le bon moment est celui que tu crées.", "Tu attends des conditions qui n’arrivent jamais.\nCommence maintenant, ajuste en route.\nLe moment parfait est un mythe qui te fige.\nRends le moment bon en bougeant."),
# 23
("Self-worth and output", "You are not your to-do list.", "Your value is not the sum of your output.\nBeing productive does not make you more worthy.\nYou already matter, before and after the work.\nTie your worth to your being, not your doing.",
 "Самоценность и продуктивность", "Ты не свой список дел.", "Твоя ценность — не сумма сделанного.\nПродуктивность не делает тебя достойнее.\nТы уже важен — до и после работы.\nПривязывай ценность к бытию, не к делам.",
 "Valeur et rendement", "Tu n’es pas ta liste de tâches.", "Ta valeur n’est pas la somme de ta production.\nÊtre productif ne te rend pas plus digne.\nTu comptes déjà, avant et après le travail.\nAttache ta valeur à ton être, pas à ton faire."),
# 24
("Fear of failure", "Fall forward — every try is data.", "Failure is information, not a verdict.\nYou learn more from the fall than from the stay.\nNot trying is the only real failure.\nThe ground is close; the sky is closer.",
 "Страх неудачи", "Падай вперёд — каждая попытка это данные.", "Неудача — информация, а не приговор.\nПадение учит больше, чем стояние на месте.\nЕдинственный настоящий провал — не пробовать.\nЗемля близко; небо ближе.",
 "Peur de l’échec", "Tombe en avant — chaque essai est une donnée.", "L’échec est une information, pas un verdict.\nTu apprends plus de la chute que de l’immobilité.\nNe pas essayer est le seul vrai échec.\nLe sol est proche ; le ciel est plus proche."),
# 25
("Black and white", "Colour the grey — life lives there.", "All-or-nothing thinking hides the middle.\nA half-done thing still counts.\nGrey is not a failure of black and white.\nMost of life happens in the in-between.",
 "Чёрное и белое", "Раскрась серое — жизнь живёт там.", "Мышление «всё или ничего» прячет середину.\nСделанное наполовину всё равно считается.\nСерое — не провал чёрного и белого.\nБольшая часть жизни — между.",
 "Tout ou rien", "Colore le gris — la vie s’y cache.", "La pensée tout-ou-rien cache le milieu.\nUne chose à moitié faite compte quand même.\nLe gris n’est pas l’échec du noir et du blanc.\nLa vie vit surtout dans l’entre-deux."),
# 26
("Hyper-responsibility", "It is not all on you.", "You feel responsible for everything — weather included.\nShare the load; it was never all yours.\nOthers’ choices are others’ choices.\nBreathe: the world spins without your grip.",
 "Гиперответственность", "Не всё лежит на тебе.", "Ты чувствуешь ответ за всё — даже за погоду.\nДелись нагрузкой; она не была только твоей.\nЧужие решения — чужие решения.\nВдохни: мир крутится без твоей хватки.",
 "Hyper-responsabilité", "Tout ne repose pas sur toi.", "Tu te sens responsable de tout — même de la météo.\nPartage la charge ; elle n’a jamais été qu’à toi.\nLes choix des autres sont les choix des autres.\nRespire : le monde tourne sans ta main."),
# 27
("Seeking reassurance", "Check in with yourself, not the world.", "You ask others to confirm what you already know.\nTrust yourself once; the loop will loosen.\nA little uncertainty is survivable.\nYour own yes is enough.",
 "Поиск подтверждений", "Сверяйся с собой, не с миром.", "Ты просишь других подтвердить то, что уже знаешь.\nДоверься себе один раз — петля ослабнет.\nНемного неопределённости переживаемо.\nТвоего собственного «да» достаточно.",
 "Chercher du réconfort", "Fais confiance à toi, pas au monde.", "Tu demandes aux autres de confirmer ce que tu sais déjà.\nFais-toi confiance une fois ; la boucle s’assouplira.\nUn peu d’incertitude est survivable.\nTon propre « oui » suffit."),
# 28
("Decision paralysis", "Any choice beats the waiting loop.", "You rehearse options until none fits.\nPick one, move, correct later.\nMistakes are reversible; standing still is not.\nA good decision today beats a perfect one never.",
 "Паралич решения", "Любой выбор бьёт петлю ожидания.", "Ты прокручиваешь варианты, пока ни один не подходит.\nВыбери, двигайся, исправляй потом.\nОшибки обратимы; стояние на месте — нет.\nХорошее решение сегодня лучше идеального — никогда.",
 "Paralysie de décision", "Tout choix bat la boucle d’attente.", "Tu répètes les options jusqu’à ce qu’aucune ne colle.\nChoisis, avance, corrige ensuite.\nLes erreurs sont réversibles ; l’immobilité ne l’est pas.\nUne bonne décision aujourd’hui vaut mieux qu’une parfaite jamais."),
# 29
("Rumination", "Replay ends. Move to the next scene.", "Rewinding the tape changes nothing.\nThe thought will pass if you let it.\nObserve it, don’t star in it.\nYour mind is a projector, not a prison.",
 "Руминация", "Перемотка кончается. Переходи к следующей сцене.", "Перемотка плёнки ничего не меняет.\nМысль пройдёт, если позволишь.\nНаблюдай за ней, а не играй главную роль.\nТвой ум — проектор, а не тюрьма.",
 "Rumination", "La relecture s’arrête. Passe à la scène suivante.", "Rembobiner la bande ne change rien.\nLa pensée passera si tu la laisses.\nObserve-la, ne la joue pas.\nTon esprit est un projecteur, pas une prison."),
# 30
("People-pleasing", "A softer no protects a truer yes.", "You bend until you disappear.\nSaying yes to everyone is saying no to you.\nA kind no is a gift to both sides.\nYour limits are valid, unapologetically.",
 "Угодливость", "Мягкое «нет» защищает честное «да».", "Ты гнёшься, пока не исчезаешь.\nГоворить «да» всем — значит «нет» себе.\nДоброе «нет» — подарок обеим сторонам.\nТвои границы важны — без извинений.",
 "Plaire à tout le monde", "Un non doux protège un oui vrai.", "Tu te plies jusqu’à disparaître.\nDire oui à tous, c’est dire non à toi.\nUn non gentil est un cadeau pour les deux.\nTes limites sont valables, sans excuses."),
# 31
("Guilt spiral", "Guilt points; it doesn’t chain you.", "You replay what you should have done differently.\nAcknowledge, learn, release.\nThe past is a teacher, not a cell.\nYou get to start over in the next breath.",
 "Спираль вины", "Вина указывает, но не держит в цепях.", "Ты прокручиваешь, что надо было сделать иначе.\nПризнай, извлеки урок, отпусти.\nПрошлое — учитель, не камера.\nТы можешь начать заново со следующим вдохом.",
 "Spirale de culpabilité", "La culpabilité indique, elle n’enchaîne pas.", "Tu rejoues ce que tu aurais dû faire autrement.\nReconnais, apprends, libère.\nLe passé est un maître, pas une cellule.\nTu peux recommencer au prochain souffle."),
# 32
("Self-sabotage", "The saboteur fears success more than failure.", "You quit right before the finish line.\nYou prove yourself wrong to avoid the risk.\nName the saboteur. Thank it. Then move on.\nYou can stand success — you have stood worse.",
 "Самосаботаж", "Саботажник боится успеха больше, чем провала.", "Ты бросаешь прямо перед финишем.\nТы доказываешь себе, что не справишься, лишь бы избежать риска.\nНазови саботажника. Поблагодари. Иди дальше.\nТы выдержишь успех — ты выдерживал худшее.",
 "Auto-sabotage", "Le saboteur craint le succès plus que l’échec.", "Tu abandonnes juste avant la ligne.\nTu te prouves à tort pour éviter le risque.\nNomme le saboteur. Remercie-le. Avance.\nTu peux supporter le succès — tu as supporté pire."),
# 33
("Unrelenting standards", "Good enough is a real finish line.", "You set bars no human can clear.\nLower the bar and you will actually jump.\n“Enough” is not a compromise; it is wisdom.\nRest is part of the standard, not a break from it.",
 "Недостижимые стандарты", "«Достаточно хорошо» — настоящий финиш.", "Ты ставишь планки, которые не перепрыгнет ни один человек.\nОпусти планку — и реально прыгнешь.\n«Достаточно» — не компромисс, а мудрость.\nОтдых — часть стандарта, а не перерыв в нём.",
 "Standards inflexibles", "«Assez bien » est une vraie ligne d’arrivée.", "Tu mets la barre trop haut pour un humain.\nBaisse-la et tu sauteras vraiment.\n« Assez » n’est pas un compromis, c’est de la sagesse.\nLe repos fait partie du standard, pas une pause."),
# 34
("Avoidance", "Do the thing that whispers.", "You dodge what feels heavy.\nAvoidance grows the monster; facing it shrinks it.\nTen minutes of the hard thing beats a day of dreading.\nThe other side of fear is lighter than fear itself.",
 "Избегание", "Сделай то, что шепчет.", "Ты уворачиваешься от тяжёлого.\nИзбегание растит монстра; встреча уменьшает его.\nДесять минут трудного бьют день тревоги.\nПо ту сторону страха легче, чем в самом страхе.",
 "Évitement", "Fais la chose qui murmure.", "Tu évites ce qui semble lourd.\nL’évitement nourrit le monstre ; l’affronter le réduit.\nDix minutes de la chose difficile battent une journée d’angoisse.\nL’autre côté de la peur est plus léger que la peur."),
# 35
("Over-preparation", "You are ready enough — begin.", "You collect one more manual, one more course.\nPreparation becomes another form of delay.\nYou already know enough to start.\nThe road teaches what the manual cannot.",
 "Переподготовка", "Ты достаточно готов — начинай.", "Ты коллекционируешь ещё одну инструкцию, ещё один курс.\nПодготовка становится ещё одной формой откладывания.\nТы уже знаешь достаточно, чтобы начать.\nДорога учит тому, чего не знает учебник.",
 "Sur-préparation", "Tu es assez prêt — commence.", "Tu accumules encore un manuel, encore un cours.\nLa préparation devient une autre forme de retard.\nTu en sais déjà assez pour commencer.\nLa route enseigne ce que le manuel ne peut pas."),
# 36
("Imposter syndrome", "They picked you for a reason.", "You feel like a fraud wearing someone’s suit.\nEveryone feels it at the edge of growth.\nYou were chosen, promoted, believed in.\nThe seat is yours. Stay.",
 "Синдром самозванца", "Тебя выбрали не случайно.", "Ты чувствуешь себя самозванцем в чужом костюме.\nТак чувствуют все на грани роста.\nТебя выбрали, повысили, в тебя поверили.\nЭто кресло твоё. Останься.",
 "Syndrome de l’imposteur", "Ils t’ont choisi pour une raison.", "Tu te sens comme un imposteur dans un costume d’emprunt.\nTout le monde le sent au bord de la croissance.\nTu as été choisi, promu, cru.\nCette place est à toi. Reste."),
# 37
("Catastrophizing", "The worst-case script is fiction.", "Your mind writes disaster endings.\nRead the probability, not the panic.\nYou have survived every hard day so far.\nMost fears are weather, not climate.",
 "Катастрофизация", "Сценарий худшего — вымысел.", "Твой ум пишет катастрофические финалы.\nЧитай вероятность, а не панику.\nТы пережил каждый трудный день до сих пор.\nБольшинство страхов — погода, а не климат.",
 "Catastrophisme", "Le scénario du pire est une fiction.", "Ton esprit écrit des fins catastrophiques.\nLis la probabilité, pas la panique.\nTu as survécu à chaque jour difficile jusqu’ici.\nLa plupart des peurs sont du temps, pas du climat."),
# 38
("Emotional reasoning", "Feelings are data, not facts.", "“I feel doomed, so it must be true.”\nFeelings are weather inside you, not verdicts.\nNotice the feeling, then check the facts.\nYou can feel wrong and still be on track.",
 "Эмоциональное мышление", "Чувства — данные, а не факты.", "«Мне кажется, всё пропало — значит, так и есть».\nЧувства — погода внутри, а не приговор.\nЗаметь чувство, затем проверь факты.\nМожно чувствовать себя неправо и при этом быть на верном пути.",
 "Raisonnement émotionnel", "Les émotions sont des données, pas des faits.", "« Je me sens perdu, donc c’est vrai. »\nLes émotions sont le temps qu’il fait en toi, pas des verdicts.\nRemarque l’émotion, puis vérifie les faits.\nTu peux te sentir mal et être pourtant sur la bonne voie."),
# 39
("All-or-nothing language", "Delete “always” and “never”.", "“I always fail”, “I never finish”.\nThose words are verdicts, not observations.\nUse “this time”, “sometimes”, “today”.\nLanguage shapes what you can do.",
 "Язык «всё или ничего»", "Удали «всегда» и «никогда».", "«Я всегда проваливаюсь», «Я никогда не довожу».\nЭто приговоры, а не наблюдения.\nГовори: «в этот раз», «иногда», «сегодня».\nЯзык формирует то, что тебе под силу.",
 "Langage tout-ou-rien", "Supprime « toujours » et « jamais ».", "« Je rate toujours », « Je ne finis jamais ».\nCes mots sont des verdicts, pas des constats.\nDis « cette fois », « parfois », « aujourd’hui ».\nLe langage façonne ce que tu peux faire."),
# 40
("Harsh self-talk", "Speak to yourself like a friend.", "You would never talk to a friend the way you talk to you.\nCatch the harsh word before it lands.\nSwap the insult for a correction.\nEncouragement is a skill; practise it on yourself.",
 "Суровая самокритика", "Говори с собой как с другом.", "Ты не говорил бы с другом так, как говоришь с собой.\nЛови резкое слово до того, как оно ударит.\nМеняй оскорбление на поправку.\nПоддержка — навык; тренируй его на себе.",
 "Parler durement à soi", "Parle-toi comme à un ami.", "Tu ne parlerais jamais à un ami comme tu te parles.\nAttrape le mot dur avant qu’il ne touche.\nRemplace l’insulte par une correction.\nL’encouragement est une compétence ; entraîne-toi dessus."),
# 41
("Over-committing", "A full plate drops everything.", "You say yes until nothing survives.\nEvery yes has a hidden no inside it.\nChoose the few things that matter.\nAn empty spot in the day is not a failure.",
 "Перегрузка обязательствами", "Переполненная тарелка роняет всё.", "Ты говоришь «да», пока ничто не выживает.\nВ каждом «да» спрятано «нет».\nВыбери немногое, что действительно важно.\nПустое место в дне — не провал.",
 "Sur-engagement", "Une assiette pleine fait tout tomber.", "Tu dis oui jusqu’à ce que rien ne survive.\nChaque oui cache un non.\nChoisis les quelques choses qui comptent.\nUne place vide dans la journée n’est pas un échec."),
# 42
("Can’t delegate", "Let go — someone else can too.", "Holding every thread burns you out.\nPerfectionism hoards the work.\nOthers may do it differently; different is okay.\nYour worth is not measured by doing it all alone.",
 "Неумение делегировать", "Отпусти — кто-то другой тоже может.", "Держать все нити — выгорание.\nПерфекционизм копит работу.\nДругие могут делать иначе; иначе — нормально.\nТвоя ценность не измеряется тем, что ты всё делаешь один.",
 "Impossible à déléguer", "Lâche prise — quelqu’un d’autre peut aussi.", "Tenir tous les fils t’épuise.\nLe perfectionnisme accapare le travail.\nD’autres peuvent faire autrement ; autrement, c’est bien.\nTa valeur ne se mesure pas à tout faire seul."),
# 43
("Perfectionist delay", "Start ugly. Ship it. Refine later.", "You wait until it feels ready — it never does.\nDone in motion beats perfect in the drawer.\nVersion one is a beginning, not a shame.\nPolishing a real thing beats dreaming of a flawless one.",
 "Перфекционистская задержка", "Начни коряво. Выпусти. Отполируй потом.", "Ты ждёшь, пока станет готово — а оно не становится.\nСделанное в движении бьёт идеальное в ящике.\nПервая версия — начало, а не стыд.\nПолировать настоящее лучше, чем мечтать о безупречном.",
 "Retard perfectionniste", "Commence moche. Livre. Affine après.", "Tu attends que ce soit prêt — ça ne l’est jamais.\nFait en mouvement bat parfait au tiroir.\nLa version un est un début, pas une honte.\nPolir une chose réelle vaut mieux que rêver d’une sans défaut."),
# 44
("Fear of criticism", "Feedback is fuel, not fire.", "You hear critique as a verdict on your worth.\nIt is information about the work, not you.\nYou can listen without agreeing.\nThe critic and the builder can coexist.",
 "Страх критики", "Обратная связь — топливо, а не огонь.", "Ты слышишь критику как приговор твоей ценности.\nЭто информация о работе, не о тебе.\nМожно слушать, не соглашаясь.\nКритик и строитель могут сосуществовать.",
 "Peur de la critique", "Le retour est du carburant, pas du feu.", "Tu entends la critique comme un verdict sur ta valeur.\nC’est une information sur le travail, pas sur toi.\nTu peux écouter sans être d’accord.\nLe critique et le bâtisseur peuvent coexister."),
# 45
("Hyper-vigilance", "Scan less. Trust more.", "You scan for threats that mostly aren’t there.\nSafety is not guaranteed; neither is disaster.\nLower the alert level — life gets quieter.\nYour body can rest without permission.",
 "Гипербдительность", "Сканируй меньше. Доверяй больше.", "Ты сканируешь угрозы, которых почти нет.\nБезопасность не гарантирована; и катастрофа — тоже.\nСнизь уровень тревоги — жизнь станет тише.\nТвоему телу можно отдыхать без разрешения.",
 "Hypervigilance", "Scanne moins. Fais confiance.", "Tu cherches des menaces qui n’y sont presque pas.\nLa sécurité n’est pas garantie ; le désastre non plus.\nBaisse l’alerte — la vie devient plus calme.\nTon corps peut se reposer sans permission."),
# 46
("Productivity = worth", "Being is enough. Doing is a bonus.", "You feel you must earn your place by output.\nThe day is not a scoreboard.\nA quiet morning still counts.\nYou exist before you achieve.",
 "Продуктивность = ценность", "Быть — достаточно. Делать — бонус.", "Ты чувствуешь, что должен заслужить место делом.\nДень — не табло очков.\nТихое утро тоже считается.\nТы существуешь до достижений.",
 "Productivité = valeur", "Être suffit. Faire est un bonus.", "Tu crois devoir gagner ta place par le rendement.\nLa journée n’est pas un tableau de scores.\nUne matinée calme compte aussi.\nTu existes avant de réussir."),
# 47
("Rest is failure", "Rest is maintenance, not defeat.", "You read a break as falling behind.\nMuscles grow during recovery, not during reps.\nA rested mind makes sharper work.\nSleep is strategy, not surrender.",
 "Отдых как провал", "Отдых — обслуживание, не поражение.", "Ты читаешь паузу как отставание.\nМышцы растут при восстановлении, а не при повторах.\nОтдохнувший ум делает работу острее.\nСон — стратегия, а не сдача.",
 "Le repos est un échec", "Le repos est entretien, pas défaite.", "Tu lis une pause comme un retard.\nLes muscles poussent pendant la récupération, pas les séries.\nUn esprit reposé fait un travail plus net.\nLe sommeil est une stratégie, pas une reddition."),
# 48
("Mirror checking", "Stop checking. Start noticing.", "You check the mirror, the face, the status.\nThe loop gives false relief, then more doubt.\nLook once, then step away.\nThe world sees you better than you fear.",
 "Зеркальное самопроверяние", "Перестань проверять. Начни замечать.", "Ты проверяешь зеркало, лицо, статус.\nПетля даёт ложное облегчение, потом новое сомнение.\nПосмотри один раз и отойди.\nМир видит тебя лучше, чем ты боишься.",
 "Contrôler dans le miroir", "Arrête de vérifier. Commence à remarquer.", "Tu vérifies le miroir, le visage, le statut.\nLa boucle soulage à faux, puis nourrit le doute.\nRegarde une fois, puis éloigne-toi.\nLe monde te voit mieux que tu ne le crains."),
# 49
("Control of emotions", "Feel it. Let it pass. Repeat.", "You fight feelings like they are enemies.\nEmotions are visitors with a schedule.\nPushing them down makes them shout.\nLet them pass through; you stay whole.",
 "Контроль эмоций", "Почувствуй. Дай пройти. Повтори.", "Ты борешься с чувствами, как с врагами.\nЭмоции — гости со своим расписанием.\nЗаталкивая их внутрь, ты заставляешь их кричать.\nПозволь им пройти; ты останешься целым.",
 "Contrôle des émotions", "Ressens. Laisse passer. Recommence.", "Tu combats les émotions comme des ennemis.\nCe sont des visiteurs avec leur emploi du temps.\nLes refouler les fait crier.\nLaisse-les passer ; tu restes entier."),
# 50
("Need for approval", "Your own nod is the one that counts.", "You outsource your worth to others’ thumbs.\nApproval is a drink that never quenches.\nLearn to nod at yourself first.\nYou are the only constant in your life.",
 "Потребность в одобрении", "Твой собственный кивок — главный.", "Ты отдаёшь свою ценность чужим лайкам.\nОдобрение — напиток, который не утоляет.\nНаучись кивать себе первым.\nТы — единственная константа своей жизни.",
 "Besoin d’approbation", "Ton propre accord est celui qui compte.", "Tu confies ta valeur aux pouces des autres.\nL’approbation est une boisson qui n’étanche pas.\nApprends à te faire un signe à toi d’abord.\nTu es la seule constante de ta vie."),
# 51
("Cognition–feeling mix", "Thoughts are not commands.", "You treat every thought as a truth to obey.\nA thought is a spark, not a verdict.\nNotice it, then choose.\nYou have veto power over your own mind.",
 "Смешение мыслей и чувств", "Мысли — не приказы.", "Ты относишься к каждой мысли как к истине.\nМысль — искра, а не приговор.\nЗаметь её, потом выбирай.\nУ тебя есть право вето над собственным умом.",
 "Pensées et émotions", "Les pensées ne sont pas des ordres.", "Tu traites chaque pensée comme une vérité à suivre.\nUne pensée est une étincelle, pas un verdict.\nRemarque-la, puis choisis.\nTu as un droit de veto sur ton propre esprit."),
# 52
("Worth from struggle", "Struggling is not failing.", "Hard means it matters, not that you’re broken.\nGrowth is loud and awkward sometimes.\nThe grunt of effort is a good sound.\nYou can struggle and still succeed.",
 "Ценность через борьбу", "Трудности — не провал.", "Сложно значит важно, а не «с тобой что-то не так».\nРост бывает громким и неловким.\nЗвук усилия — хороший звук.\nМожно бороться и при этом побеждать.",
 "Valeur dans l’effort", "Lutter n’est pas échouer.", "Difficile signifie que ça compte, pas que tu es cassé.\nLa croissance est parfois bruyante et maladroite.\nLe son de l’effort est un bon son.\nTu peux lutter et réussir."),
# 53
("Perfectionist memory", "You were not perfect then either — and it was fine.", "You replay past mistakes with a harsh filter.\nEveryone was a beginner, you included.\nThe past is data, not a mirror to punish yourself in.\nYou survived every version of you.",
 "Перфекционистская память", "Ты и тогда не был идеальным — и это было нормально.", "Ты перематываешь прошлые ошибки с жёстким фильтром.\nВсе были новичками, включая тебя.\nПрошлое — данные, а не зеркало для самобичевания.\nТы выжил в каждой своей версии.",
 "Mémoire perfectionniste", "Tu n’étais pas parfait alors non plus — et c’était bien.", "Tu rejoues les erreurs passées avec un filtre dur.\nTout le monde a été débutant, toi compris.\nLe passé est une donnée, pas un miroir pour te punir.\nTu as survécu à chaque version de toi."),
# 54
("Hidden comparison", "Compare only to yesterday’s you.", "You scroll and shrink next to others’ lives.\nTheir path has no bearing on yours.\nMeasure your arc, not their snapshot.\nProgress is a private conversation.",
 "Скрытое сравнение", "Сравнивай только с собой вчерашним.", "Ты листаешь ленту и сжимаешься рядом с чужими жизнями.\nИх путь не имеет отношения к твоему.\nИзмеряй свою дугу, не их кадр.\nПрогресс — приватный разговор.",
 "Comparaison cachée", "Compare seulement à ton hier.", "Tu défiles et rapetisses à côté des vies des autres.\nLeur chemin ne regarde pas le tien.\nMesure ton arc, pas leur instantané.\nLe progrès est une conversation privée."),
# 55
("Perfect wording", "Say it plainly. It lands better.", "You rewrite the message until it dies.\nSimple words carry more than polished ones.\nSend the honest version today.\nClarity beats eloquence.",
 "Идеальная формулировка", "Скажи просто. Так дойдёт лучше.", "Ты переписываешь сообщение, пока оно не умирает.\nПростые слова несут больше отполированных.\nОтправь честную версию сегодня.\nЯсность бьёт красноречие.",
 "Formulation parfaite", "Dis-le simplement. Ça passera mieux.", "Tu réécris le message jusqu’à le tuer.\nLes mots simples portent plus que les polis.\nEnvoie la version honnête aujourd’hui.\nLa clarté bat l’éloquence."),
# 56
("Checklist life", "The list is a tool, not a judge.", "You measure your day by what got crossed off.\nSome days are for being, not doing.\nThe unchecked box is not a crime.\nYour life is wider than a to-do list.",
 "Жизнь по чек-листу", "Список — инструмент, а не судья.", "Ты измеряешь день тем, что вычеркнул.\nНекоторые дни для бытия, а не дел.\nНезачёркнутый пункт — не преступление.\nТвоя жизнь шире списка дел.",
 "La vie en liste", "La liste est un outil, pas un juge.", "Tu mesures ta journée à ce qui est coché.\nCertains jours sont pour être, pas pour faire.\nLa case vide n’est pas un crime.\nTa vie est plus large qu’une liste de tâches."),
# 57
("Fear of starting", "The first minute is the hardest. Take it.", "The start looms larger than the whole task.\nYour resistance is loudest at the threshold.\nCommit to sixty seconds — momentum takes over.\nBeginning is the whole trick.",
 "Страх начала", "Первая минута самая трудная. Сделай её.", "Начало кажется больше всей задачи.\nСопротивление громче всего на пороге.\nДоговорись на шестьдесят секунд — дальше понесёт.\nНачало — и есть весь секрет.",
 "Peur de commencer", "La première minute est la plus dure. Prends-la.", "Le début semble plus grand que toute la tâche.\nLa résistance est la plus forte au seuil.\nEngage-toi sur soixante secondes — l’élan prend le relais.\nCommencer est tout le secret."),
# 58
("Perfect environment", "Start where you are, with what you have.", "You wait for the tidy desk, the free morning.\nTools are enough the moment you begin.\nThe right conditions are made, not found.\nNow is a fine place to start.",
 "Идеальная среда", "Начни там, где ты, с тем, что есть.", "Ты ждёшь чистого стола, свободного утра.\nИнструментов достаточно в момент старта.\nНужные условия создаются, а не находятся.\nЗдесь и сейчас — отличное место для старта.",
 "Environnement parfait", "Commence où tu es, avec ce que tu as.", "Tu attends le bureau rangé, la matinée libre.\nLes outils suffisent dès que tu commences.\nLes bonnes conditions se font, ne se trouvent pas.\nIci et maintenant est un bon endroit."),
# 59
("One more try", "The next try is not proof of failure.", "One miss does not rewrite your whole story.\nStatistically, persistence usually wins.\nThe next attempt is fresh, not contaminated.\nTry again: it is allowed.",
 "Ещё одна попытка", "Следующая попытка — не доказательство провала.", "Один промах не переписывает всю историю.\nСтатистически упорство обычно побеждает.\nСледующая попытка новая, а не испорченная.\nПробуй снова: это разрешено.",
 "Un essai de plus", "Le prochain essai n’est pas la preuve de l’échec.", "Un raté ne réécrit pas toute l’histoire.\nStatistiquement, la persévérance gagne.\nLe prochain essai est neuf, pas contaminé.\nRéessaie : c’est permis."),
# 60
("Hiding imperfection", "Your flaws make you legible.", "You hide the crack as if it cancels you.\nCracks let light in — literally and otherwise.\nPeople connect to honest edges.\nShowing the seam is a kind of courage.",
 "Скрытие несовершенства", "Твои изъяны делают тебя читаемым.", "Ты прячешь трещину, будто она отменяет тебя.\nТрещины пропускают свет — буквально и нет.\nЛюдей цепляют честные грани.\nПоказать шов — вид смелости.",
 "Cacher l’imperfection", "Tes défauts te rendent lisible.", "Tu caches la fissure comme si elle t’annulait.\nLes fissures laissent passer la lumière — au sens propre et figuré.\nLes gens se connectent aux bords honnêtes.\nMontrer la couture est une sorte de courage."),
# 61
("Waiting for motivation", "Action arrives before motivation.", "You wait to feel ready — the feeling lags.\nDo, and the mood follows like a dog.\nMotivation is a reward, not a requirement.\nMove first; fire comes after.",
 "Ожидание мотивации", "Действие приходит раньше мотивации.", "Ты ждёшь готовности — а чувство опаздывает.\nДействуй, и настроение пойдёт следом, как собака.\nМотивация — награда, а не требование.\nДвигайся первым; огонь загорится после.",
 "Attendre la motivation", "L’action vient avant la motivation.", "Tu attends de te sentir prêt — le sentiment traîne.\nAgis, et l’humeur suit comme un chien.\nLa motivation est une récompense, pas une condition.\nBouge d’abord ; le feu vient après."),
# 62
("Mistake catastrophizing", "A slip is a step, not a fall.", "One error feels like the whole tower falling.\nIt is a single stone, not the wall.\nCorrect, adjust, continue.\nRecovery is the real skill.",
 "Катастрофизация ошибок", "Сбой — шаг, а не падение.", "Одна ошибка ощущается крушением всей башни.\nЭто один камень, а не стена.\nИсправь, подстройся, продолжай.\nВосстановление — настоящее умение.",
 "Catastrophe de l’erreur", "Un faux pas est un pas, pas une chute.", "Une erreur semble faire tomber toute la tour.\nC’est une pierre, pas le mur.\nCorrige, ajuste, continue.\nLa reprise est la vraie compétence."),
# 63
("Deserving rest", "You do not have to earn a pause.", "Rest feels like a debt you must justify.\nYour battery does not negotiate.\nA break is not a prize for achievement.\nYou deserve stillness simply by existing.",
 "Право на отдых", "Паузу не нужно заслуживать.", "Отдых ощущается долгом, который надо оправдать.\nТвоя батарея не торгуется.\nПерерыв — не награда за достижения.\nТы заслуживаешь тишины просто потому, что существуешь.",
 "Mériter le repos", "Tu n’as pas à gagner une pause.", "Le repos semble une dette à justifier.\nTa batterie ne négocie pas.\nUne pause n’est pas un prix pour la réussite.\nTu mérites le calme simplement en existant."),
# 64
("Future perfection", "The future has no better starting point.", "You postpone for a version of you that never comes.\nFuture-you will face the same mess.\nToday-you is already the right one.\nLend the future a hand: start.",
 "Идеальное будущее", "У будущего нет лучшей точки старта.", "Ты откладываешь для версии себя, которая не наступит.\nБудущий ты столкнётся с тем же хаосом.\nСегодняшний ты — уже подходящий.\nПротяни будущему руку: начни.",
 "Perfection future", "Le futur n’a pas de meilleur point de départ.", "Tu remets à une version de toi qui ne vient jamais.\nLe toi futur verra le même désordre.\nLe toi d’aujourd’hui est déjà le bon.\nTends la main au futur : commence."),
# 65
("Overthinking outcomes", "Most outcomes are out of your hands.", "You spin every possibility to feel in control.\nControl is a feeling, not a fact.\nDo your part, then release the rest.\nLet the world be as unpredictable as it is.",
 "Переобдумывание исходов", "Большинство исходов не в твоих руках.", "Ты крутишь все варианты, чтобы чувствовать контроль.\nКонтроль — чувство, а не факт.\nСделай своё, отпусти остальное.\nПозволь миру быть таким же непредсказуемым, как он есть.",
 "Sur-penser les résultats", "La plupart des issues échappent à tes mains.", "Tu tournes chaque possibilité pour te sentir en contrôle.\nLe contrôle est un sentiment, pas un fait.\nFais ta part, puis lâche le reste.\nLaisse le monde être aussi imprévisible qu’il est."),
# 66
("Fear of being seen", "Visible is not vulnerable in the bad way.", "You fear being watched, judged, weighed.\nBeing seen is how connection happens.\nYour work and you deserve light.\nStep into view; the glare fades fast.",
 "Страх быть замеченным", "Быть видимым — не значит уязвимым в плохом смысле.", "Ты боишься, что за тобой смотрят, судят, взвешивают.\nБыть увиденным — так возникает связь.\nТвоя работа и ты заслуживаете света.\nВыйди на свет; жар быстро уходит.",
 "Peur d’être vu", "Être visible n’est pas être vulnérable.", "Tu crains d’être regardé, jugé, pesé.\nÊtre vu, c’est ainsi que naît le lien.\nTon travail et toi méritez la lumière.\nEntre dans la lumière ; l’éblouissement passe vite."),
# 67
("Exact planning", "Plan less. Adjust more.", "You demand a map with every turn drawn.\nLife hands you detours anyway.\nA rough direction beats a rigid plan.\nThe best route reveals itself by walking.",
 "Идеальное планирование", "Планируй меньше. Подстраивайся больше.", "Ты требуешь карту с каждым поворотом.\nЖизнь всё равно подкинет объезды.\nГрубое направление лучше жёсткого плана.\nЛучший маршрут открывается в движении.",
 "Planification exacte", "Planifie moins. Ajuste plus.", "Tu exiges une carte avec chaque virage.\nLa vie offre des détours de toute façon.\nUne direction large bat un plan rigide.\nLe meilleur itinéraire se révèle en marchant."),
# 68
("Self-blame loop", "Forgiveness is not a reward for being perfect.", "You stay on yourself as a strategy to improve.\nSelf-blame does not motivate; it paralyzes.\nCorrect without crucifying.\nYou grow faster with kindness.",
 "Петля самобичевания", "Прощение — не награда за идеальность.", "Ты держишь себя в ежовых рукавицах ради роста.\nСамобичевание не мотивирует — оно парализует.\nИсправляй без распятия.\nС добротой ты растёшь быстрее.",
 "Boucle d’auto-blâme", "Le pardon n’est pas une récompense pour être parfait.", "Tu te culpabilises comme stratégie d’amélioration.\nL’auto-blâme ne motive pas ; il paralyse.\nCorrige sans crucifier.\nTu grandis plus vite avec la douceur."),
# 69
("Watching others succeed", "Their win is not your loss.", "Someone else’s progress feels like your setback.\nThere is no fixed amount of success.\nTheir light does not dim yours.\nYou can cheer and still pursue your own.",
 "Успехи других", "Их победа — не твоё поражение.", "Чужой прогресс ощущается твоей неудачей.\nУспеха не ограниченное количество.\nИх свет не гасит твой.\nМожно радоваться за других и идти к своему.",
 "Voir les autres réussir", "Leur victoire n’est pas ta perte.", "Le progrès des autres semble être ton recul.\nLe succès n’est pas en quantité fixe.\nLeur lumière n’éteint pas la tienne.\nTu peux applaudir et poursuivre le tien."),
# 70
("Perfect communication", "Clarity beats perfect phrasing.", "You rehearse the ideal sentence forever.\nPeople want meaning, not poetry.\nSay it plainly, once, kindly.\nThe message matters more than the messenger’s polish.",
 "Идеальное общение", "Ясность бьёт идеальные формулировки.", "Ты вечно репетируешь идеальную фразу.\nЛюдям нужен смысл, а не поэзия.\nСкажи просто, один раз, доброжелательно.\nСообщение важнее шлифовки говорящего.",
 "Communication parfaite", "La clarté bat la phrase parfaite.", "Tu répètes la phrase idéale à l’infini.\nLes gens veulent du sens, pas de la poésie.\nDis-le simplement, une fois, avec bonté.\nLe message compte plus que le poli de l’orateur."),
# 71
("Fear of wasting time", "Spent well means spent in motion.", "You fear any hour that isn’t maximised.\nWandering is part of the work.\nNot everything needs a yield.\nA day lived is a day well used.",
 "Страх потерянного времени", "Прожито хорошо — значит в движении.", "Ты боишься любого часа, который не максимально полезен.\nБлуждание — часть работы.\nНе всему нужна отдача.\nПрожитый день — хорошо использованный день.",
 "Peur de perdre du temps", "Bien dépensé, c’est dépensé en mouvement.", "Tu crains toute heure non maximisée.\nFlâner fait partie du travail.\nTout n’a pas besoin de rendement.\nUn jour vécu est un jour bien utilisé."),
# 72
("Perfect routine", "A routine that lasts beats one that’s flawless.", "You design a schedule no human could keep.\nFlexibility is a feature, not a flaw.\nSkip a day and still be on the team.\nShow up imperfectly, but show up.",
 "Идеальная рутина", "Рутина, которая держится, бьёт безупречную.", "Ты проектируешь график, который не выдержит ни один человек.\nГибкость — функция, а не изъян.\nПропусти день и останься в игре.\nПриходи неидеальным, но приходи.",
 "Routine parfaite", "Une routine qui dure bat une routine parfaite.", "Tu conçois un emploi du temps qu’aucun humain ne tient.\nLa flexibilité est une fonction, pas un défaut.\nSaute un jour et reste dans l’équipe.\nViens imparfait, mais viens."),
# 73
("Others’ expectations", "Their script is not your role.", "You perform to expectations you never agreed to.\nLiving for others’ applause empties your stage.\nDecide whose life you are directing.\nTheir opinion is a signal, not a command.",
 "Чужие ожидания", "Их сценарий — не твоя роль.", "Ты играешь по ожиданиям, на которые не подписывался.\nЖизнь ради чужих аплодисментов опустошает сцену.\nРеши, чью жизнь ты режиссируешь.\nИх мнение — сигнал, а не приказ.",
 "Attentes des autres", "Leur scénario n’est pas ton rôle.", "Tu joues selon des attentes que tu n’as jamais acceptées.\nVivre pour les applaudissements des autres vide ta scène.\nDécide de la vie que tu diriges.\nLeur avis est un signal, pas un ordre."),
# 74
("Progress resetting", "Evening resets are not failures.", "You judge the day by its lowest hour.\nA whole day is a long curve, not a single point.\nYou stumbled and still stand.\nTomorrow is the same project, not a verdict.",
 "Сброс прогресса", "Вечерний сброс — не провал.", "Ты судишь день по его худшему часу.\nВесь день — длинная кривая, а не одна точка.\nТы споткнулся и всё ещё стоишь.\nЗавтра — тот же проект, а не приговор.",
 "Réinitialiser le progrès", "Les réinitialisations du soir ne sont pas des échecs.", "Tu juges la journée par sa pire heure.\nUne journée entière est une longue courbe, pas un point.\nTu as trébuché et tu tiens toujours debout.\nDemain est le même projet, pas un verdict."),
# 75
("Hidden effort", "Your unseen work still counts.", "You think if it wasn’t hard, it wasn’t real.\nSmooth days are built on many rough ones.\nThe easy version is still a version.\nWhat looked effortless took everything you had.",
 "Невидимые усилия", "Твоя невидимая работа всё равно считается.", "Ты думаешь: если было легко — значит, не по-настоящему.\nГладкие дни строятся на многих шершавых.\nЛёгкая версия — всё равно версия.\nТо, что выглядело простым, стоило всех сил.",
 "Effort invisible", "Ton travail invisible compte aussi.", "Tu crois que si ce n’était pas dur, ce n’était pas réel.\nLes jours lisses se construisent sur de nombreux rudes.\nLa version facile est une version.\nCe qui semblait facile t’a coûté tout."),
# 76
("Comparing now to then", "Your old highlight reel is not today’s standard.", "You judge today against your best year.\nSeasons differ; so do you.\nThe peak and the valley are the same mountain.\nToday is allowed to be different.",
 "Сравнение с прошлым", "Твоя старая лента успеха — не сегодняшний стандарт.", "Ты судишь сегодня по своему лучшему году.\nСезоны разные; и ты разный.\nПик и долина — одна гора.\nСегодня может быть другим.",
 "Comparer hier et aujourd’hui", "Ton ancien fil de réussite n’est pas le standard d’aujourd’hui.", "Tu juges aujourd’hui avec ta meilleure année.\nLes saisons diffèrent ; toi aussi.\nLe sommet et la vallée sont la même montagne.\nAujourd’hui a le droit d’être différent."),
# 77
("Perfection as identity", "You are not your output’s quality.", "You believe being imperfect means being less.\nYou are a person first, a doer second.\nYour worth survives a bad draft.\nIdentity is bigger than performance.",
 "Перфекционизм как идентичность", "Ты не качество своей работы.", "Ты веришь, что быть неидеальным — быть меньшим.\nТы человек прежде всего, делатель — во вторую очередь.\nТвоя ценность переживёт черновик.\nИдентичность шире результата.",
 "Perfection comme identité", "Tu n’es pas la qualité de ta production.", "Tu crois qu’être imparfait, c’est être moins.\nTu es une personne d’abord, un acteur ensuite.\nTa valeur survit à un brouillon.\nL’identité est plus grande que la performance."),
# 78
("Holding patterns", "You can hold steady and still be moving.", "Not every day needs visible progress.\nRoots grow underground before leaves show.\nA holding pattern is still a course.\nPatience is a form of action.",
 "Удерживание позиции", "Можно держать курс и при этом двигаться.", "Не каждому дню нужен видимый прогресс.\nКорни растут под землёй до появления листьев.\nПаттерн удержания — тоже курс.\nТерпение — форма действия.",
 "Maintien de cap", "Tu peux tenir bon et bouger en même temps.", "Tous les jours n’ont pas besoin de progrès visible.\nLes racines poussent sous terre avant les feuilles.\nRester en cap est une trajectoire.\nLa patience est une forme d’action."),
# 79
("Gift of being ordinary", "Ordinary is the foundation of extraordinary.", "You crave specialness in every move.\nThe ordinary is where most of life actually lives.\nBeing unremarkable is not being worthless.\nConsistency makes ordinary into magic.",
 "Дар обычности", "Обычное — фундамент необычного.", "Ты жаждешь особости в каждом движении.\nОбычное — где живёт большая часть жизни.\nБыть неприметным — не быть никчёмным.\nПостоянство превращает обычное в магию.",
 "Le don de l’ordinaire", "L’ordinaire est le fondement de l’extraordinaire.", "Tu convoites la particularité à chaque geste.\nL’ordinaire est là où vit la plupart de la vie.\nÊtre banal n’est pas être sans valeur.\nLa constance transforme l’ordinaire en magie."),
# 80
("Fear of regret", "A small risk now beats a big “what if” later.", "You avoid decisions to avoid later regret.\nNot choosing is also a choice with its own cost.\nRegret shrinks when you act from your values.\nYou can revise — life allows it.",
 "Страх сожалений", "Маленький риск сейчас лучше большого «что если» потом.", "Ты избегаешь решений, чтобы избежать сожалений.\nНе выбирать — тоже выбор со своей ценой.\nСожаление сжимается, когда действуешь по своим ценностям.\nПересмотреть можно — жизнь позволяет.",
 "Peur des regrets", "Un petit risque maintenant vaut mieux qu’un grand « et si » plus tard.", "Tu évites les décisions pour éviter les regrets.\nNe pas choisir est aussi un choix avec son coût.\nLe regret rétrécit quand tu agis selon tes valeurs.\nTu peux réviser — la vie le permet."),
# 81
("Perfect first draft", "First drafts are for existing.", "You expect the first version to be finished art.\nEvery draft is a beginning, by design.\nUgly first, better second, good third.\nThe first page exists to be rewritten.",
 "Идеальный черновик", "Первые черновики нужны, чтобы существовать.", "Ты ждёшь, что первая версия будет законченным искусством.\nКаждый черновик — начало, по замыслу.\nКоряво сначала, лучше во второй, хорошо в третий.\nПервая страница существует, чтобы её переписали.",
 "Premier brouillon parfait", "Les premiers brouillons servent à exister.", "Tu attends que la première version soit une œuvre finie.\nChaque brouillon est un début, par conception.\nMoche d’abord, mieux ensuite, bien au troisième.\nLa première page existe pour être réécrite."),
# 82
("Approval habits", "Earned trust beats gathered likes.", "You collect approvals like trophies on a shelf.\nApproval is a mirror that changes shape.\nTrust your own assessment more often.\nThe crowd is not your jury.",
 "Привычка к одобрению", "Заработанное доверие бьёт собранные лайки.", "Ты собираешь одобрения, как трофеи на полке.\nОдобрение — зеркало, меняющее форму.\nЧаще доверяй собственной оценке.\nТолпа — не твой суд.",
 "Habitudes d’approbation", "La confiance gagnée bat les likes récoltés.", "Tu accumules les approbations comme des trophées.\nL’approbation est un miroir qui change de forme.\nFais plus souvent confiance à ton propre jugement.\nLa foule n’est pas ton jury."),
# 83
("Body overthinking", "Your body is a compass, not a complaint.", "You analyse every signal until it screams.\nThe body often speaks in whispers first.\nSoften the focus; listen without diagnosing.\nMovement and breath can settle the noise.",
 "Переобдумывание тела", "Тело — компас, а не жалоба.", "Ты анализируешь каждый сигнал, пока он не закричит.\nТело обычно сначала говорит шёпотом.\nСмягчи фокус; слушай без диагнозов.\nДвижение и дыхание могут успокоить шум.",
 "Sur-penser le corps", "Ton corps est une boussole, pas une plainte.", "Tu analyses chaque signal jusqu’à ce qu’il crie.\nLe corps parle d’abord en chuchotant.\nAdoucis le focus ; écoute sans diagnostiquer.\nLe mouvement et le souffle calment le bruit."),
# 84
("Second-guessing", "Trust the choice you already made.", "You change your answer ten times to avoid wrongness.\nDouble-checking becomes a loop with no exit.\nYour first instinct carries your accumulated knowledge.\nDecide, then defend it only if needed.",
 "Перепроверка", "Доверься выбору, который уже сделал.", "Ты меняешь ответ десять раз, лишь бы не ошибиться.\nПерепроверка становится петлёй без выхода.\nВ первом импульсе — весь твой накопленный опыт.\nРеши, а защищай только при необходимости.",
 "Douter de soi", "Fais confiance au choix que tu as déjà fait.", "Tu changes ta réponse dix fois pour éviter l’erreur.\nLa re-vérification devient une boucle sans issue.\nTon premier instinct porte ton savoir accumulé.\nDécide, puis défends seulement si nécessaire."),
# 85
("Others’ pace", "Run beside your own clock.", "You measure your speed against someone else’s mile.\nThey started elsewhere; the track differs.\nFast and slow both reach the end.\nYour pace is your pace — honour it.",
 "Чужой темп", "Беги рядом со своими часами.", "Ты измеряешь свою скорость чужой милей.\nОни стартовали в другом месте; дорожка другая.\nБыстрые и медленные оба доходят до конца.\nТвой темп — твой темп. Уважай его.",
 "Rythme des autres", "Cours au rythme de ta propre horloge.", "Tu mesures ta vitesse sur le mile d’un autre.\nIls ont commencé ailleurs ; la piste diffère.\nRapides et lents arrivent tous au bout.\nTon rythme est ton rythme — honore-le."),
# 86
("Perfect endings", "Endings don’t need to be tidy.", "You want every chapter to close cleanly.\nLoose threads are honest to life.\nNot every story needs a ribbon.\nAn open end is not an unfinished failure.",
 "Идеальные финалы", "Финал не обязан быть аккуратным.", "Ты хочешь, чтобы каждая глава закрывалась чисто.\nНезакрытые концы честны по отношению к жизни.\nНе каждой истории нужен бант.\nОткрытый конец — не провал.",
 "Fins parfaites", "Les fins n’ont pas besoin d’être nettes.", "Tu veux que chaque chapitre se ferme proprement.\nLes fils lâches sont honnêtes à la vie.\nToutes les histoires n’ont pas besoin de ruban.\nUne fin ouverte n’est pas un échec."),
# 87
("Winning the wrong game", "Make sure the goal is yours.", "You chase trophies you never really wanted.\nAsk: whose finish line is this?\nA prize you don’t value is a heavy one.\nChoose the game before you play it.",
 "Победа не в своей игре", "Убедись, что цель твоя.", "Ты гонишься за трофеями, которых на самом деле не хотел.\nСпроси: чей это финиш?\nНаграда, которую не ценишь, — тяжёлая ноша.\nВыбирай игру до того, как играть.",
 "Gagner au mauvais jeu", "Assure-toi que l’objectif est à toi.", "Tu poursuis des trophées que tu ne voulais pas vraiment.\nDemande : à qui est cette ligne d’arrivée ?\nUn prix que tu n’estimes pas est lourd.\nChoisis le jeu avant de jouer."),
# 88
("Hidden fatigue", "Tiredness is a signal, not a weakness.", "You push through fatigue as if it were laziness.\nExhaustion is a message worth reading.\nPacing beats grinding.\nA rested you is a stronger you.",
 "Скрытая усталость", "Усталость — сигнал, а не слабость.", "Ты продавливаешь усталость, будто это лень.\nИстощение — сообщение, которое стоит прочитать.\nРавномерный темп бьёт изматывание.\nОтдохнувший ты — более сильный ты.",
 "Fatigue cachée", "La fatigue est un signal, pas une faiblesse.", "Tu forces à travers la fatigue comme si c’était de la paresse.\nL’épuisement est un message à lire.\nLe rythme mesuré bat l’acharnement.\nUn toi reposé est un toi plus fort."),
# 89
("Perfection in others", "Their perfection is also a filter.", "You admire others’ smooth lives and shrink.\nEveryone curates; no one is flat.\nThe glossy version hides the grind too.\nCompare raw to raw, not cut to cut.",
 "Чужая идеальность", "Их идеальность — тоже фильтр.", "Ты любуешься чужими гладкими жизнями и сжимаешься.\nВсе курируют; никто не плоский.\nГлянцевая версия тоже прячет труд.\nСравнивай сырое с сырым, а не кадр с кадром.",
 "Perfection chez les autres", "Leur perfection est aussi un filtre.", "Tu admires les vies lisses des autres et rapetisses.\nTout le monde organise ; personne n’est plat.\nLa version brillante cache aussi l’effort.\nCompare le brut au brut, pas la coupe à la coupe."),
# 90
("Worth while waiting", "You are enough right now — not later.", "You promise yourself worth after the milestone.\nThe future prize never arrives on time.\nThe present version deserves kindness now.\nYou don’t have to be done to be enough.",
 "Ценность в ожидании", "Ты достаточен прямо сейчас — не потом.", "Ты обещаешь себе ценность после вехи.\nБудущий приз никогда не приходит вовремя.\nНынешняя версия заслуживает доброты сейчас.\nНе нужно быть готовым, чтобы быть достаточным.",
 "Valeur en attendant", "Tu suffis maintenant — pas plus tard.", "Tu te promets de la valeur après l’étape.\nLe prix futur n’arrive jamais à l’heure.\nLa version actuelle mérite la douceur maintenant.\nPas besoin d’être fini pour suffire."),
# 91
("Overchecking", "One look is enough. Walk on.", "You check the lock, the message, the word.\nEach check feeds the next doubt.\nThe loop only deepens by repeating.\nConfirm once, then trust the first result.",
 "Перепроверка всего", "Одного взгляда достаточно. Иди дальше.", "Ты проверяешь замок, сообщение, слово.\nКаждая проверка питает следующее сомнение.\nПетля углубляется от повторений.\nПодтверди один раз и доверься первому результату.",
 "Vérifier trop", "Un coup d’œil suffit. Avance.", "Tu vérifies la serrure, le message, le mot.\nChaque vérification nourrit le doute suivant.\nLa boucle s’approfondit en répétant.\nConfirme une fois, puis fie-toi au premier résultat."),
# 92
("Deserving a chance", "You are allowed to try — no permit needed.", "You wait for permission you already hold.\nTrying is not a reward; it is a right.\nBegin without a licence.\nThe door is open; you just have to walk.",
 "Право на попытку", "Тебе можно пробовать — разрешение не нужно.", "Ты ждёшь разрешения, которое уже есть у тебя в руках.\nПопытка — не награда, а право.\nНачинай без лицензии.\nДверь открыта; осталось войти.",
 "Mériter sa chance", "Tu as le droit d’essayer — pas besoin de permis.", "Tu attends une permission que tu détiens déjà.\nEssayer n’est pas une récompense, c’est un droit.\nCommence sans licence.\nLa porte est ouverte ; il reste à entrer."),
# 93
("Perfectionist praise", "Let the good land for a second.", "You deflect compliments like debris.\nReceiving is not arrogance; it is hygiene.\nSay thank you, then let it settle.\nYou can accept praise without believing every word.",
 "Перфекционизм и похвала", "Дай хорошему опуститься на секунду.", "Ты отбиваешь комплименты, как обломки.\nПринимать — не высокомерие, а гигиена.\nСкажи спасибо и дай этому осесть.\nМожно принять похвалу, не веря каждому слову.",
 "Compliments et perfectionnisme", "Laisse le bien se poser une seconde.", "Tu repousses les compliments comme des débris.\nRecevoir n’est pas de l’arrogance ; c’est de l’hygiène.\nDis merci, puis laisse reposer.\nTu peux accepter un éloge sans croire chaque mot."),
# 94
("Fear of boredom", "Boredom is space, not failure.", "You fill every minute to feel worthwhile.\nBoredom lets the mind stretch and breathe.\nEmpty time is not wasted time.\nA quiet moment is fertile ground.",
 "Страх скуки", "Скука — пространство, а не провал.", "Ты заполняешь каждую минуту, чтобы чувствовать пользу.\nСкука даёт уму потянуться и вдохнуть.\nПустое время — не потерянное время.\nТихий момент — плодородная почва.",
 "Peur de l’ennui", "L’ennui est un espace, pas un échec.", "Tu remplis chaque minute pour te sentir utile.\nL’ennui laisse l’esprit s’étirer et respirer.\nLe temps vide n’est pas du temps perdu.\nUn moment calme est un sol fertile."),
# 95
("Perfect support", "Lean on others before you fall.", "You insist on doing it all alone to prove strength.\nAsking for help is a skill, not a failure.\nPeople want to be there for you.\nStrength includes knowing when to lean.",
 "Идеальная опора", "Опирайся на других, пока не упал.", "Ты настаиваешь делать всё в одиночку, чтобы доказать силу.\nПросить о помощи — навык, а не провал.\nЛюди хотят быть рядом с тобой.\nСила включает умение опереться.",
 "Soutien parfait", "Appuie-toi sur les autres avant de tomber.", "Tu tiens à tout faire seul pour prouver ta force.\nDemander de l’aide est une compétence, pas un échec.\nLes gens veulent être là pour toi.\nLa force sait aussi quand s’appuyer."),
# 96
("Result worship", "The process is where you actually live.", "You fixate on the trophy and miss the road.\nYou spend the journey in the result’s shadow.\nThe doing is the life; the outcome is the echo.\nShow up for the process and the rest follows.",
 "Поклонение результату", "В процессе ты и живёшь по-настоящему.", "Ты фиксируешься на трофее и пропускаешь дорогу.\nТы проводишь путь в тени результата.\nДелание — жизнь; исход — эхо.\nПриходи ради процесса — остальное последует.",
 "Adorer le résultat", "C’est dans le processus que tu vis vraiment.", "Tu fixes le trophée et rates la route.\nTu passes le voyage à l’ombre du résultat.\nLe faire est la vie ; le résultat est l’écho.\nViens pour le processus, le reste suivra."),
# 97
("Perfect apology", "An honest sorry is enough.", "You over-engineer apologies to be flawless.\nSincerity beats a perfect script.\nAdmit, repair, move on.\nThe fix matters more than the phrasing.",
 "Идеальное извинение", "Честного «прости» достаточно.", "Ты переделываешь извинения до безупречности.\nИскренность бьёт идеальный сценарий.\nПризнай, исправь, иди дальше.\nИсправление важнее формулировки.",
 "Excusés parfaits", "Un « pardon » sincère suffit.", "Tu sur-conçois des excuses impeccables.\nLa sincérité bat un script parfait.\nReconnais, répare, avance.\nLa réparation compte plus que la phrase."),
# 98
("Everyone’s expectations", "You cannot hold the whole world’s weight.", "You absorb everyone’s wants as your own duty.\nTheir unmet hopes are theirs to carry.\nBe good, not everything to everyone.\nYour shoulders have their own limits.",
 "Всеобщие ожидания", "Ты не можешь нести вес всего мира.", "Ты впитываешь чужие желания как свой долг.\nИх несбывшиеся надежды — их ноша.\nБудь хорошим, а не всем для всех.\nУ твоих плеч есть свои пределы.",
 "Attentes de tous", "Tu ne peux pas porter le poids du monde.", "Tu absorbes les désirs des autres comme ton devoir.\nLeurs espoirs déçus sont leur fardeau.\nSois bon, pas tout pour tous.\nTes épaules ont leurs propres limites."),
# 99
("Fear of being average", "Average day, average effort — still a life.", "You panic at being unremarkable.\nMost greatness is built from many average days.\nMediocrity is not a verdict; it is a phase.\nShowing up average is still showing up.",
 "Страх быть посредственным", "Обычный день, обычное усилие — и всё же жизнь.", "Ты паникуешь от непримечательности.\nБольшая часть величия построена из множества обычных дней.\nПосредственность — не приговор, а фаза.\nПриходить обычным — всё равно приходить.",
 "Peur d’être moyen", "Jour moyen, effort moyen — et pourtant une vie.", "Tu paniques à l’idée d’être banal.\nLa grandeur naît de nombreux jours moyens.\nLa médiocrité n’est pas un verdict ; c’est une phase.\nVenir moyen, c’est encore venir."),
# 100
("Final message", "You were never meant to be perfect.", "The chase for perfection was never the point.\nYou are human: messy, changing, enough.\nLet the standards soften around you.\nLive, try, fail, and stay.",
 "Финальное послание", "Ты никогда не должен был быть идеальным.", "Погоня за совершенством никогда не была целью.\nТы человек: неаккуратный, меняющийся, достаточный.\nПозволь стандартам смягчиться вокруг тебя.\nЖиви, пробуй, ошибайся и оставайся.",
 "Message final", "Tu n’as jamais été censé être parfait.", "La quête de la perfection n’a jamais été le but.\nTu es humain : désordonné, changeant, suffisant.\nLaisse les standards s’adoucir autour de toi.\nVis, essaie, échoue et reste."),
]

# Icons and colors: pairs reused across 80 cards
ICONS = [
    "Icons.balance_outlined", "Icons.auto_awesome_outlined", "Icons.psychology_outlined",
    "Icons.track_changes", "Icons.explore", "Icons.spa_outlined",
    "Icons.self_improvement", "Icons.lightbulb_outline", "Icons.sensors",
    "Icons.tune_outlined", "Icons.ac_unit_outlined", "Icons.gradient_outlined",
    "Icons.emoji_objects", "Icons.visibility_outlined", "Icons.help_outline_outlined",
    "Icons.favorite_border_outlined", "Icons.loop_outlined", "Icons.hourglass_empty_outlined",
    "Icons.aspect_ratio_outlined", "Icons.water_drop_outlined", "Icons.eco_outlined",
    "Icons.waves_outlined", "Icons.public_outlined", "Icons.rocket_launch_outlined",
    "Icons.forest_outlined", "Icons.cloud_outlined", "Icons.nightlight_outlined",
    "Icons.wb_sunny_outlined", "Icons.star_border_outlined", "Icons.bolt_outlined",
    "Icons.extension_outlined", "Icons.handshake_outlined", "Icons.toll_outlined",
    "Icons.air_outlined", "Icons.shield_outlined", "Icons.flag_outlined",
    "Icons.terrain_outlined", "Icons.navigation_outlined", "Icons.sunny_snowing",
    "Icons.cycle_outlined", "Icons.temple_hindu_outlined", "Icons.church_outlined",
    "Icons.cottage_outlined", "Icons.cabin_outlined", "Icons.holiday_village_outlined",
    "Icons.door_sliding_outlined", "Icons.window_outlined", "Icons.deck_outlined",
    "Icons.crib_outlined", "Icons.bathtub_outlined", "Icons.coffee_outlined",
    "Icons.local_cafe_outlined", "Icons.restaurant_outlined", "Icons.kebab_dining_outlined",
    "Icons.icecream_outlined", "Icons.cake_outlined", "Icons.bakery_dining_outlined",
    "Icons.lunch_dining_outlined", "Icons.dinner_dining_outlined", "Icons.set_meal_outlined",
    "Icons.ramen_dining_outlined", "Icons.soup_kitchen_outlined", "Icons.egg_outlined",
    "Icons.free_breakfast_outlined", "Icons.brunch_dining_outlined", "Icons.rice_bowl_outlined",
    "Icons.emoji_food_beverage_outlined", "Icons.cooked_outlined", "Icons.fastfood_outlined",
    "Icons.room_service_outlined", "Icons.liquor_outlined", "Icons.wine_bar_outlined",
    "Icons.self_improvement_outlined", "Icons.accessibility_new_outlined", "Icons.airline_seat_flat_outlined",
    "Icons.directions_walk_outlined", "Icons.hiking_outlined", "Icons.pool_outlined",
    "Icons.sports_gymnastics_outlined", "Icons.sports_martial_arts_outlined",
]

COLORS = [
    "Color(0xFFB39DDB)", "Color(0xFF7B61FF)", "Color(0xFF80D8FF)", "Color(0xFFFFAB91)",
    "Color(0xFFFFD54F)", "Color(0xFFFF8A80)", "Color(0xFF80CBC4)", "Color(0xFFFFB74D)",
    "Color(0xFF90A4AE)", "Color(0xFFAED9E0)", "Color(0xFFCE93D8)", "Color(0xFF80DEEA)",
    "Color(0xFFF06292)", "Color(0xFF4DD0E1)", "Color(0xFFFFCA28)", "Color(0xFF9FA8DA)",
    "Color(0xFF81C784)", "Color(0xFFFF8A65)", "Color(0xFFBA68C8)", "Color(0xFF4DB6AC)",
    "Color(0xFFA1887F)", "Color(0xFF7986CB)", "Color(0xFF4FC3F7)", "Color(0xFFFFE082)",
    "Color(0xFFA5D6A7)", "Color(0xFFF48FB1)", "Color(0xFF64B5F6)", "Color(0xFFFFCC80)",
    "Color(0xFFB0BEC5)", "Color(0xFFB39DD8)", "Color(0xFF81D4FA)", "Color(0xFFFFF59D)",
]

assert len(CARDS) == 80, f"expected 80 cards, got {len(CARDS)}"

# 1) Build habits_screen.dart plaque entries
plaque_lines = []
for idx, card in enumerate(CARDS, start=21):
    icon = ICONS[(idx - 21) % len(ICONS)]
    color = COLORS[(idx - 21) % len(COLORS)]
    plaque_lines.append("  _PerfPlaque(")
    plaque_lines.append(f"    titleKey: 'perfTitle{idx}',")
    plaque_lines.append(f"    bodyKey: 'perf{idx}Full',")
    plaque_lines.append(f"    shortKey: 'perf{idx}Short',")
    plaque_lines.append(f"    icon: {icon},")
    plaque_lines.append(f"    color: {color},")
    plaque_lines.append("  ),")

with open('scripts/_plaques_screen.txt', 'w', encoding='utf-8') as f:
    f.write("\n".join(plaque_lines) + "\n")

# 2) Build translation lines for each language block
def trans_lines(cards, num):
    lines = []
    for idx, card in enumerate(cards, start=21):
        t, s, fl = card[num], card[num+1], card[num+2]
        lines.append(f"      'perfTitle{idx}': '{t}',")
        lines.append(f"      'perf{idx}Short': '{s}',")
        # escape backslash-n
        fl_esc = fl.replace("\\", "\\\\").replace("'", "\\'")
        lines.append(f"      'perf{idx}Full': '{fl_esc}',")
    return lines

en_lines = trans_lines(CARDS, 0)
ru_lines = trans_lines(CARDS, 3)
fr_lines = trans_lines(CARDS, 6)

with open('scripts/_plaques_en.txt', 'w', encoding='utf-8') as f:
    f.write("\n".join(en_lines) + "\n")
with open('scripts/_plaques_ru.txt', 'w', encoding='utf-8') as f:
    f.write("\n".join(ru_lines) + "\n")
with open('scripts/_plaques_fr.txt', 'w', encoding='utf-8') as f:
    f.write("\n".join(fr_lines) + "\n")

print("Generated:", len(CARDS), "cards")
print("screen entries:", len(plaque_lines), "lines")
print("en:", len(en_lines), "ru:", len(ru_lines), "fr:", len(fr_lines))
