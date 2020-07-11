#include "Player.h"
#include "card.generated.h"

#include <iostream>
#include <algorithm>

/* Card/Player section */


Player::Player(queue<DeferredEvent*>& _event_queue) : field(), hand(), deck(), event_queue(_event_queue)
{
}

Player::Player(const string& _name, int _hp, const vector<Card*>& _deck, bool _is_guest, queue<DeferredEvent*>& _event_queue) : name(_name), is_lost(false), is_turn_active(false), turn_num(0), max_mp(0), mp_loss(0), fatigue(0), field(), hand(), deck(_deck), field_size_adjust(0), hand_size_adjust(0), deck_size_adjust(0), is_guest(_is_guest), is_exploration(false), event_queue(_event_queue), input_func(&Player::TakeInputs)
{
	leader = CreateDefaultLeader(_hp);
	leader->card_pos = CARD_POS_AT_LEADER;
	for (auto it = deck.begin(); it != deck.end(); it++)
		(*it)->card_pos = CARD_POS_AT_DECK;
}

Player::Player(const string & _name, int _hp, const vector<Card*>& _deck, bool _is_guest, queue<DeferredEvent*>& _event_queue, unsigned _ai_level) : Player(_name, _hp, _deck, _is_guest, _event_queue)
{
	ai_level = _ai_level;
	if (ai_level > 9)
		ai_level = 9;
	else if (ai_level < 0)
		ai_level = 0;

	if (ai_level == 0)
		input_func = &Player::TakeRandomAIInputs;
	else
		input_func = &Player::TakeSearchAIInputs;
}

Player::~Player()
{
	delete leader; // leader is never moved so don't need to check
	for (auto it = field.begin(); it != field.end(); it++)
		if (*it) // moved cards/minions may temperorily become nullptr
			delete (*it);
	for (auto it = hand.begin(); it != hand.end(); it++)
		if (*it) // moved cards/minions may temperorily become nullptr
			delete (*it);
	for (auto it = deck.begin(); it != deck.end(); it++)
		if (*it) // moved cards/minions may temperorily become nullptr
			delete (*it);
}

Player* Player::CreateKnowledgeCopy(unsigned mode, queue<DeferredEvent*>& event_queue, PtrRedirMap& redir_map) const
{
	Player* new_player = new Player(event_queue);

	// leader, field, hand, and deck
	new_player->leader = leader->CreateHardCopy(redir_map);
	for (auto it = field.begin(); it != field.end(); it++)
	{
		Card* tmp_card = *it;
		new_player->field.push_back(tmp_card->CreateHardCopy(redir_map));
	}
	for (auto it = hand.begin(); it != hand.end(); it++)
	{
		Card* tmp_card = *it;
		if (mode == COPY_OPPO)
			new_player->hand.push_back(GenerateCard(GetRandInt()));
		else
			new_player->hand.push_back(tmp_card->CreateHardCopy(redir_map));
	}
	for (auto it = deck.begin(); it != deck.end(); it++)
	{
		Card* tmp_card = *it;
		new_player->deck.push_back(GenerateCard(GetRandInt()));
	}

	// other status, note: do not need to assign the opponent as the opponent must alse be copied in order for exploration to work (after they are both copied they the opponent pointers needs to be set to the copy of each other)
	new_player->name = name;
	new_player->is_guest = is_guest;
	new_player->is_exploration = true;
	new_player->is_lost = is_lost;
	new_player->is_turn_active = is_turn_active;
	new_player->turn_num = turn_num;
	new_player->max_mp = max_mp;
	new_player->mp_loss = mp_loss;
	new_player->fatigue = fatigue;
	new_player->field_size_adjust = field_size_adjust;
	new_player->hand_size_adjust = hand_size_adjust;
	new_player->deck_size_adjust = deck_size_adjust;

	return new_player;
}

void Player::RegisterCardContributions(vector<int>& counters)
{
	auto counter_it = counters.begin();
	for (auto it = deck.begin(); it != deck.end() && counter_it != counters.end(); it++, counter_it++)
		(*it)->RegisterContribution(&(*counter_it));
}

void Player::SetAllCardAfflications()
{
	SetCardAfflication(leader);
	for (auto it = field.begin(); it != field.end(); it++)
		SetCardAfflication(*it);
	for (auto it = hand.begin(); it != hand.end(); it++)
		SetCardAfflication(*it);
	for (auto it = deck.begin(); it != deck.end(); it++)
		SetCardAfflication(*it);
}

void Player::SetCardAfflication(Card* card)
{
	card->SetAffiliation(this);
}

void Player::InitialCardDraw(bool is_second_player)
{
	bool start_of_batch = true;
	for (int i = 0; i < INIT_HAND_SIZE && !deck.empty(); i++)
	{
		// skip spots/cards queued for deletion
		vector<Card*>::iterator it;
		if (!deck.empty())
		{
			it = deck.end() - 1;
			while (it != deck.begin() && (!(*it) || (*it)->is_dying))
				it--;
		}
		else
			break;

		// no fatigue for initial draw (not happening for a normal rule anyway)
		if (deck.empty() || ((*it) && !(*it)->is_dying))
		{
			Card* card = *it;
			deck.erase(it);
			FlagHandPut(card, start_of_batch);
			start_of_batch = false;
		}
	}

	if (is_second_player)
	{
		Card* token = CreateSndPlayerToken();
		FlagHandPut(token, start_of_batch);
		SetCardAfflication(token);
	}

	CleanUp();
}

bool Player::CleanUp()
{
	if (CheckGameEnd()) // check for possible game end from some special win condition beyond leader health smaller or equal to zero
	{
		// make sure to clear corpse so that when printing the final board, the nullptrs caused by moved cards doesn't mess up
		ClearCorpse();
		opponent->ClearCorpse();
		return true;
	}

	if (ProcessDeferredEvents()) // leader destruction is checked here
	{
		// make sure to clear corpse so that when printing the final board, the nullptrs caused by moved cards doesn't mess up
		ClearCorpse();
		opponent->ClearCorpse();
		return true;
	}

	ClearCorpse();
	opponent->ClearCorpse();

	return false;
}

bool Player::ProcessDeferredEvents()
{
	while (!event_queue.empty())
	{		
		DeferredEvent* event = event_queue.front();
		event_queue.pop();
		event->Process(this);
		delete event;
		if (CheckGameEnd())
		{
			while (!event_queue.empty()) // check the remaining queue until the end of current batch for potential draw for the match
			{
				DeferredEvent* tmp_event = event_queue.front();
				if (tmp_event->is_start_of_batch)
					break;
				event_queue.pop();
				tmp_event->Process(this);
				delete tmp_event;
			}
			return true;
		}
	}

	return CheckGameEnd();
}

void Player::ClearCorpse()
{
	// leader (only check for resetting)
	if (leader->is_resetting)
	{
		leader->ClearExtraEffects();
		leader->is_resetting = false;
	}

	// field
	for (int i = field.size() - 1; i >= 0; i--)
	{
		Card* tmp_card = field[i];
		if (!tmp_card) // for moved minions
		{
			field.erase(field.begin() + i);
			field_size_adjust++;
		}
		else if (tmp_card->is_resetting) // a dying card cannot have its state reset (or affected by any effects), so if it is both resetting and dying it must be reset first, so we check for resetting first
		{
			tmp_card->ClearExtraEffects();
			tmp_card->is_resetting = false; // don't forget to set it back
		}
		else if (tmp_card->is_dying) // for transformed/destroyed/discarded minions
		{
			if (tmp_card->replacement) // transformed
			{
				field[i] = tmp_card->replacement;
				delete tmp_card;
			}
			else // destroyed/discarded
			{
				field.erase(field.begin() + i);
				delete tmp_card;
				field_size_adjust++;
			}
		}
	}

	// hand
	for (int i = hand.size() - 1; i >= 0; i--)
	{
		Card* tmp_card = hand[i];
		if (!tmp_card) // for moved cards
		{
			hand.erase(hand.begin() + i);
			hand_size_adjust++;
		}
		else if (tmp_card->is_resetting) // a dying card cannot have its state reset (or affected by any effects), so if it is both resetting and dying it must be reset first, so we check for resetting first
		{
			tmp_card->ClearExtraEffects();
			tmp_card->is_resetting = false; // don't forget to set it back
		}
		else if (tmp_card->is_dying) // for transformed/cast/discarded cards
		{
			if (tmp_card->replacement) // transformed
			{
				hand[i] = tmp_card->replacement;
				delete tmp_card;
			}
			else // cast/discarded
			{
				hand.erase(hand.begin() + i);
				delete tmp_card;
				hand_size_adjust++;
			}
		}
	}

	// deck
	for (int i = deck.size() - 1; i >= 0; i--)
	{
		Card* tmp_card = deck[i];
		if (!tmp_card) // for moved cards
		{
			deck.erase(deck.begin() + i);
			deck_size_adjust++;
		}
		else if (tmp_card->is_resetting) // a dying card cannot have its state reset (or affected by any effects), so if it is both resetting and dying it must be reset first, so we check for resetting first
		{
			tmp_card->ClearExtraEffects();
			tmp_card->is_resetting = false; // don't forget to set it back
		}
		else if (tmp_card->is_dying) // for transformed/discarded cards
		{
			if (tmp_card->replacement) // transformed
			{
				deck[i] = tmp_card->replacement;
				delete tmp_card;
			}
			else // discarded
			{
				deck.erase(deck.begin() + i);
				delete tmp_card;
				deck_size_adjust++;
			}
		}
	}
}

bool Player::CheckGameEnd()
{
	if (CheckLose() || opponent->CheckLose())
	{
		// don't actually need to print board here, as game ended must because of turn start, turn end or other actions, where the board will be printed
		// if were printing board make sure to CleanUp before doing so to avoid nullptr issues
		is_turn_active = false;
		return true;
	}

	return false;
}

void Player::FlagDestroy(Card* card, bool start_of_batch)
{
	card->is_dying = true;
	event_queue.push(new DestroyEvent(card, start_of_batch));
	field_size_adjust--;
}

void Player::FlagCastSpell(Card* card, bool start_of_batch)
{
	card->is_dying = true;
	event_queue.push(new CastEvent(card, start_of_batch));
	hand_size_adjust--;
}

void Player::FlagFieldDiscard(Card* card, bool start_of_batch)
{
	card->is_dying = true;
	event_queue.push(new DiscardEvent(card, start_of_batch));
	field_size_adjust--;
}

void Player::FlagHandDiscard(Card* card, bool start_of_batch)
{
	card->is_dying = true;
	event_queue.push(new DiscardEvent(card, start_of_batch));
	hand_size_adjust--;
}

void Player::FlagDeckDiscard(Card* card, bool start_of_batch)
{
	card->is_dying = true;
	event_queue.push(new DiscardEvent(card, start_of_batch));
	deck_size_adjust--;
}

void Player::FlagFieldSummon(Card* card, bool start_of_batch)
{
	event_queue.push(new FieldSummonEvent(card, start_of_batch, this));
	field_size_adjust++;
	if (GetActualFieldSize() > MAX_FIELD_SIZE) // if field is full, also issue a discard event
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << name << "'s field is full." << endl;
		#endif
		FlagFieldDiscard(card, false); // the discard caused by a card movement is considered in the same batch as the movement
	}
}

void Player::FlagHandPut(Card* card, bool start_of_batch)
{
	event_queue.push(new HandPutEvent(card, start_of_batch, this));
	hand_size_adjust++;
	if (GetActualHandSize() > MAX_HAND_SIZE) // if hand is full, also issue a discard event
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << name << "'s hand is full." << endl;
		#endif
		FlagHandDiscard(card, false); // the discard caused by a card movement is considered in the same batch as the movement
	}
}

void Player::FlagDeckShuffle(Card* card, bool start_of_batch)
{
	event_queue.push(new DeckShuffleEvent(card, start_of_batch, this));
	deck_size_adjust++;
}

void Player::FlagCardTransform(Card* card, bool start_of_batch, Card* replacement)
{
	card->is_dying = true;
	event_queue.push(new CardTransformEvent(card, start_of_batch, replacement));
}

void Player::FlagCardReset(Card* card, bool start_of_batch)
{
	card->is_resetting = true;
	event_queue.push(new CardResetEvent(card, start_of_batch));
}

void Player::SetLose()
{
	is_turn_active = false;
	is_lost = true;
}

bool Player::CheckLose() const
{
	return is_lost;
}

void Player::StartTurn()
{
	turn_num++;

	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		cout << name << "\'s Turn " << turn_num << " starts." << endl << endl;
	#endif

	if (max_mp < MAX_MP)
		max_mp += 1;
	mp_loss = 0;

	// clear consumed attack times, also turn off the is_first_turn_at_field flag
	RecoverAttackTimes(); // needs to happen before turn starting effects (otherwise newly spawned/moved cards) may be allowed to attack immediately when they should not be

	// turn starting effects
	int total_cards = 2 + field.size() + hand.size() + deck.size() + opponent->field.size() + opponent->hand.size() + opponent->deck.size();
	vector<Card*> tmp_card_list; // create a temp list so that cards newly added by effects during the process does not affect the indexing (and are not considered for triggering turn start effects)
	for (int i = 0; i < total_cards; i++)
		tmp_card_list.push_back(GetTargetCard(i));
	for (int i = 0; i < total_cards; i++)
	{
		Card* card = tmp_card_list[i];
		if (card && !card->is_dying)
			card->TurnStart(leader);
		if (ProcessDeferredEvents()) return;
	}
	if (CleanUp()) return; // can't cleanup in the loop because it the effects may destory minions/discard cards

	// draw card at the start of turn
	DrawCard(true);
	if (CleanUp()) return;

	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		PrintBoard();
	#endif

	is_turn_active = true;
}

void Player::EndTurn()
{
	is_turn_active = false;

	// turn ending effects
	int total_cards = 2 + field.size() + hand.size() + deck.size() + opponent->field.size() + opponent->hand.size() + opponent->deck.size();
	vector<Card*> tmp_card_list; // create a temp list so that cards newly added by effects during the process does not affect the indexing (and are not considered for triggering turn end effects)
	for (int i = 0; i < total_cards; i++)
		tmp_card_list.push_back(GetTargetCard(i));
	for (int i = 0; i < total_cards; i++)
	{
		Card* card = tmp_card_list[i];
		if (card && !card->is_dying)
			card->TurnEnd(leader);
		if (ProcessDeferredEvents()) return;
	}
	if (CleanUp()) return; // can't cleanup in the loop because it the effects may destory minions/discard cards

	// clear overheat counters, allied cards only (should be after turn ending effects)
	leader->SetAllOverheatCounts(0);
	for (int i = 0; i < field.size(); i++)
		field[i]->SetAllOverheatCounts(0);
	for (int i = 0; i < hand.size(); i++)
		hand[i]->SetAllOverheatCounts(0);
	for (int i = 0; i < deck.size(); i++)
		deck[i]->SetAllOverheatCounts(0);

	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
	{
		PrintBoard();
		cout << "Turn ends." << endl << endl;
	}
	#endif

	// force draw if maximum number of turns has been reached
	if (turn_num >= MAX_NUM_TURNS && opponent->turn_num >= MAX_NUM_TURNS)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << "Maximun number of turns reached." << endl;
		#endif
		SetLose();
		opponent->SetLose();
	}
}

bool Player::CheckPlayValid(int x, int y, int& z)
{
	if (x == z)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration && !is_guest)
			cout << "Error: Cannot target itself." << endl << endl;
		#endif
		return false;
	}

	int i = x - (field.size() + opponent->field.size() + 2);
	if (i >= hand.size())
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration && !is_guest)
			cout << "Error: Invalid card numbering." << endl << endl;
		#endif
		return false;
	}

	Card* card = hand[i];
	if (!CheckMP(card->mana))
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration && !is_guest)
			cout << "Error: Not enough MP." << endl << endl;
		#endif
		return false;
	}

	// validate target, note that for targets of minion and hero card, if there are no valid target at all, it will return true but z will be set to -1 (target ignored and effect not triggered), z is passed by reference
	if (!card->CheckPlayValid(x, y, z))
		return false;

	return true;
}

void Player::Play(int x, int y, int z)
{
	int i = x - (field.size() + opponent->field.size() + 2);
	Card* card = hand[i];
	
	UseMP(card->mana);
	if (card->card_type != SPELL_CARD)
		hand.erase(hand.begin() + i);
	card->Play(x, y, z);	

	CleanUp();

	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		PrintBoard();
	#endif
}

bool Player::CheckAttackValid(int x, int z)
{
	if (x < 0 || x > field.size())
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration && !is_guest)
			cout << "Error: Invalid attacker numbering." << endl << endl;
		#endif
		return false;
	}

	Card* card = (x == 0 ? leader : field[x - 1]);
	if (!card->CheckAttackValid(x, z))
		return false;

	return true;
}

void Player::Attack(int x, int z)
{
	Card* card = (x == 0 ? leader : field[x - 1]);

	card->Attack(x, z);

	Card* target = (z == field.size() + opponent->field.size() + 1 ? opponent->leader : opponent->field[z - field.size() - 1]);

	CleanUp();

	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		PrintBoard();
	#endif
}

void Player::DrawCard(bool start_of_batch)
{
	// skip spots/cards queued for deletion
	vector<Card*>::iterator it;
	if (!deck.empty())
	{
		it = deck.end() - 1;
		while (it != deck.begin() && (!(*it) || (*it)->is_dying))
			it--;
	}

	if (deck.empty() || !(*it) || (*it)->is_dying)
	{
		fatigue++;
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << "Suffering fatigue: " << fatigue << "." << endl << endl;
		#endif
		leader->TakeDamage(fatigue, nullptr, true);
		return;
	}
	
	// add to hand
	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		cout << name << " draws the card " << (*it)->name << "." << endl;
	#endif
	Card* card = *it;
	deck.erase(it);
	FlagHandPut(card, start_of_batch);
}

void Player::RecoverAttackTimes()
{
	leader->n_atks_loss = 0;
	leader->is_first_turn_at_field = false;
	for (auto it = field.begin(); it != field.end(); it++)
	{
		(*it)->n_atks_loss = 0;
		(*it)->is_first_turn_at_field = false;
	}
}

bool Player::CheckMP(int cost) const
{
	return mp_loss + cost <= max_mp;
}

void Player::UseMP(int cost)
{
	mp_loss += cost;
}

void Player::ModifyMp(int amount)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		cout << abs(amount) << " MP" << (amount >= 0 ? " restored to " : " exhausted from ") << name << endl;
	#endif
	if (mp_loss < amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << "Actually only restored " << mp_loss << "." << endl;
		#endif
		mp_loss = 0;
	}
	else if (mp_loss > max_mp + amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << "Actually only exhausted " << max_mp - mp_loss << "." << endl;
		#endif
		mp_loss = max_mp;
	}
	else
	{
		mp_loss -= amount;
	}
}

void Player::ModifyMaxMp(int amount)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!is_exploration)
		cout << abs(amount) << " Max MP (and MP)" << (amount >= 0 ? " added to " : " lost from ") << name << endl;
	#endif
	if (max_mp < -amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
		{
			cout << "Actually only lost " << max_mp << " Max MP." << endl;
			cout << "Actually only lost " << max_mp - mp_loss << " MP" << endl;
		}
		#endif
		max_mp = 0;
		mp_loss = 0;
	}
	else if (max_mp > MAX_MP - amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!is_exploration)
			cout << "Actually only added " << MAX_MP - max_mp << " Max MP." << endl;
		#endif
		int mp_loss_correction = max_mp + amount - MAX_MP;
		if (mp_loss < mp_loss_correction)
		{
			#ifndef SUPPRESS_ALL_MSG
			if (!is_exploration)
				cout << "Actually only added " << MAX_MP - max_mp + mp_loss << " MP." << endl;
			#endif
			mp_loss = 0;
		}
		else
		{
			mp_loss -= mp_loss_correction;
		}
		max_mp = MAX_MP;
	}
	else
	{
		if (max_mp - mp_loss < -amount)
		{
			#ifndef SUPPRESS_ALL_MSG
			if (!is_exploration)
				cout << "Actually only lost " << max_mp - mp_loss << " MP." << endl;
			#endif
			mp_loss = max_mp + amount;
		}
		max_mp += amount;
	}
}

bool Player::IsValidTarget(int z) const
{
	return z >= 0 && z <= field.size() + opponent->field.size() + hand.size() + 1;
}

bool Player::IsValidCharTarget(int z) const
{
	return z >= 0 && z <= field.size() + opponent->field.size() + 1;
}

bool Player::IsValidMinionTarget(int z) const
{
	return z > 0 && z <= field.size() + opponent->field.size();
}

bool Player::IsValidCardTarget(int z) const
{
	return z > field.size() + opponent->field.size() + 1 && z <= field.size() + opponent->field.size() + hand.size() + 1;
}

bool Player::IsTargetAlly(int z) const
{
	return z <= field.size() || (z > field.size() + opponent->field.size() + 1 && z <= field.size() + hand.size() + deck.size() + opponent->field.size() + 1);
}

bool Player::IsTargetOpponent(int z) const
{
	return (z > field.size() && z <= field.size() + opponent->field.size() + 1) || z > field.size() + hand.size() + deck.size() + opponent->field.size() + 1;
}

Card* Player::GetTargetCard(int z) const
{
	// The index ordering is leader - field - opponent field - opponent leader - hand - deck - opponent deck - opponent hand
	if (z < 0)
		return nullptr;
	if (z == 0)
		return leader;
	z -= 1;
	if (z < field.size())
		return field[z];
	z -= field.size();
	if (z < opponent->field.size())
		return opponent->field[z];
	z -= opponent->field.size();
	if (z == 0)
		return opponent->leader;
	z -= 1;
	if (z < hand.size())
		return hand[z];
	z -= hand.size();
	if (z < deck.size())
		return deck[z];
	z -= deck.size();
	if (z < opponent->deck.size())
		return opponent->deck[z];
	z -= opponent->deck.size();
	if (z < opponent->hand.size())
		return opponent->hand[z];
	return nullptr;
}

Card* Player::ExtractTargetCard(int z)
{
	if (z <= 0)
		return nullptr;
	z -= 1;
	if (z < field.size())
	{
		Card* target = field[z];
		if (!target || target->is_dying)
			return nullptr;
		field[z] = nullptr;
		field_size_adjust--;
		return target;
	}
	z -= field.size();
	if (z < opponent->field.size())
	{
		Card* target = opponent->field[z];
		if (!target || target->is_dying)
			return nullptr;
		opponent->field[z] = nullptr;
		opponent->field_size_adjust--;
		return target;
	}
	z -= opponent->field.size();
	if (z == 0)
		return nullptr;
	z -= 1;
	if (z < hand.size())
	{
		Card* target = hand[z];
		if (!target || target->is_dying)
			return nullptr;
		hand[z] = nullptr;
		hand_size_adjust--;
		return target;
	}
	z -= hand.size();
	if (z < deck.size())
	{
		Card* target = deck[z];
		if (!target || target->is_dying)
			return nullptr;
		deck[z] = nullptr;
		deck_size_adjust--;
		return target;
	}
	z -= deck.size();
	if (z < opponent->deck.size())
	{
		Card* target = opponent->deck[z];
		if (!target || target->is_dying)
			return nullptr;
		opponent->deck[z] = nullptr;
		opponent->deck_size_adjust--;
		return target;
	}
	z -= opponent->deck.size();
	if (z < opponent->hand.size())
	{
		Card* target = opponent->hand[z];
		if (!target || target->is_dying)
			return nullptr;
		opponent->hand[z] = nullptr;
		opponent->hand_size_adjust--;
		return target;
	}
	return nullptr;
}

void Player::SummonToField(Card* card)
{
	field.push_back(card);
	card->IncContribution();
	card->card_pos = CARD_POS_AT_FIELD;
	card->SetAffiliation(this);
	card->is_first_turn_at_field = true;
	card->n_atks_loss = 0;	
}

void Player::PutToHand(Card* card)
{
	hand.push_back(card);
	card->IncContribution();
	card->card_pos = CARD_POS_AT_HAND;
	card->SetAffiliation(this);
	card->is_first_turn_at_field = false;
	card->n_atks_loss = 0;
}

void Player::ShuffleToDeck(Card* card)
{
	int index = GetRandInt(deck.size() + 1);
	deck.insert(deck.begin() + index, card);
	card->card_pos = CARD_POS_AT_DECK;
	card->SetAffiliation(this);
	card->is_first_turn_at_field = false;
	card->n_atks_loss = 0;
}

double Player::GetHeuristicEval() const
{
	if (CheckLose())
	{
		if (opponent->CheckLose()) // draw
			return 0.0;
		else // loss
			return -1.0;
	}
	else 
	{
		if (opponent->CheckLose()) // win
			return 1.0;
		else // other cases (game does not end)
		{
			bool almost_win = false;
			bool almost_lose = false;

			// collect ally strength information
			int effective_ally_atk = leader->atk * leader->max_n_atks;
			int effective_ally_hp = leader->max_hp - leader->hp_loss; // note this is mostly considering leader's hp
			if (deck.empty() && turn_num < MAX_NUM_TURNS) // if we don't have next turn then we don't need to consider fatigue (it is possible the game has not ended yet as the opponent may still has a turn)
				effective_ally_hp -= fatigue;
			for (auto it = field.begin(); it != field.end(); it++)
			{
				Card* tmp_minion = *it;
				effective_ally_atk += tmp_minion->atk * tmp_minion->max_n_atks;
				if (!leader->is_taunt && tmp_minion->is_taunt) // minion only contribute to effective hp if it has taunt (and the leader does not)
					effective_ally_hp += tmp_minion->max_hp - tmp_minion->hp_loss;
			}
			
			// collect opponent strength information
			int effective_oppo_atk = opponent->leader->atk * opponent->leader->max_n_atks;
			int effective_oppo_hp = opponent->leader->max_hp - opponent->leader->hp_loss; // note this is mostly considering leader's hp
			if (opponent->deck.empty()) // do not need to check for max turn number because if opponent has completed the last turn then at this point the game would have already ended in a draw (we only use the heuristic as end of turn evaluation) 
				effective_oppo_hp -= opponent->fatigue;
			if (effective_oppo_hp <= 0) // opponent will first take the next fatigure damage so this is ALMOST a gauranteed win (not 100% as turn start effects triggers before card draw, and there can also be divine shield on leaders etc.)
				almost_win = true;
			for (auto it = opponent->field.begin(); it != opponent->field.end(); it++)
			{
				Card* tmp_minion = *it;
				effective_oppo_atk += tmp_minion->atk * tmp_minion->max_n_atks;
				if (!opponent->leader->is_taunt && tmp_minion->is_taunt) // minion only contribute to effective hp if it has taunt (and the leader does not)
					effective_oppo_hp += tmp_minion->max_hp - tmp_minion->hp_loss;
			}

			// opponent will attack next turn (and then allied leader suffers fatigue) so this will be a check point for a potentially ALMOST gauranteed loss
			if (effective_ally_hp <= effective_oppo_atk)
				almost_lose = true;

			// the rest cases are considered with a comparison of the "strength info", plus other considerations like hand size and deck size
			double ally_hand_adjust = 0.9 * (hand.size() == MAX_HAND_SIZE ? MAX_HAND_SIZE - 1 : hand.size());
			double ally_deck_adjust = -0.9 * (MAX_NUM_TURNS - turn_num)/((double)(deck.size()) + 0.5);
			double oppo_hand_adjust = 0.9 * (opponent->hand.size() == MAX_HAND_SIZE ? MAX_HAND_SIZE - 1 : opponent->hand.size());
			double oppo_deck_adjust = -0.9 * (MAX_NUM_TURNS - opponent->turn_num)/ ((double)(opponent->deck.size()) + 0.5);
			double total_diff = (effective_ally_atk + effective_ally_hp + ally_hand_adjust + ally_deck_adjust) - (effective_oppo_atk + effective_oppo_hp + oppo_hand_adjust + oppo_deck_adjust);
			double raw_eval = total_diff / 30.0; // the 30.0 is the HP of the default leaders (well it should be a reasonable scaling factor)

			if (almost_win)
			{
				raw_eval = 0.9 + raw_eval * 0.1;
				if (raw_eval > 1.0)
					return 1.0;
				else if (raw_eval < 0.9)  // not very likely
					return 0.9;
				else
					return raw_eval;
			}
			else if (almost_lose)
			{
				raw_eval = -0.9 + raw_eval * 0.1;
				if (raw_eval < -1.0)
					return -1.0;
				else if (raw_eval > -0.9)  // not very likely
					return -0.9;
				else
					return raw_eval;
			}
			else
			{
				if (raw_eval > 0.9)
					return 0.9;
				else if (raw_eval < -0.9)
					return -0.9;
				else
					return raw_eval;
			}
		}
	}
}

vector<ActionSetEntity*> Player::GetOptionSet()
{
	vector<ActionSetEntity*> option_set;

	// possible play actions
	for (int i = field.size() + opponent->field.size() + 2; i <= field.size() + opponent->field.size() + hand.size() + 1; i++)
	{
		PlayActionSet* tmp_set = new PlayActionSet(i);
		if (tmp_set->CreateValidSet(this) > 0)
			option_set.push_back(tmp_set);
		else
			delete tmp_set;
	}

	// possible attack actions
	for (int i = 0; i <= field.size(); i++)
	{
		AttackActionSet* tmp_set = new AttackActionSet(i);
		if (tmp_set->CreateValidSet(this) > 0)
			option_set.push_back(tmp_set);
		else
			delete tmp_set;
	}

	// end turn action, which is always an option
	EndTurnActionSet* tmp_set = new EndTurnActionSet();
	tmp_set->CreateValidSet(this);
	option_set.push_back(tmp_set);

	return option_set;
}

void Player::TakeSearchAIInputs()
{
	while (is_turn_active)
		TakeSearchAIInput();
}

void Player::TakeSearchAIInput()
{
	queue<DeferredEvent*> event_queue;
	PtrRedirMap redir_map;
	KnowledgeState knowledge_state(this, event_queue, redir_map);
	knowledge_state.PerformAction();

	while (!event_queue.empty())
	{
		delete event_queue.front(); // note: this is not deleting the actual card but the entity for flagging
		event_queue.pop();
	}
}

void Player::TakeRandomAIInputs()
{
	while (is_turn_active)
		TakeRandomAIInput();
}

void Player::TakeRandomAIInput()
{
	vector<ActionSetEntity*> option_set = GetOptionSet();

	int i = GetRandInt(option_set.size());
	option_set[i]->PerformRandomAction(this);

	for (auto it = option_set.begin(); it != option_set.end(); it++)
		delete (*it);
}

void Player::TakeInputs()
{
	while (is_turn_active)
		TakeSingleInput();
}

void Player::TakeSingleInput()
{
	char command_ch;
	
	bool valid_type_found = false;
	
	int x, y, z;
	while (!valid_type_found)
	{
		cin >> command_ch;
		switch (command_ch)
		{
		case 'P':
		case 'p':
			if (cin >> x >> y >> z)
			{
				cout << "Playing card " << x << " at position " << y << " targetting at " << z << "." << endl << endl; //echo
				if (CheckPlayValid(x, y, z))
					Play(x, y, z);		
			}
			else
			{
				cout << "Format error." << endl << endl;
				DisplayHelp();
			}
			valid_type_found = true;
			break;				
		case 'A':
		case 'a':
			if (cin >> x >> z)
			{
				cout << "Commanding " << x << " to attack " << z << "." << endl << endl; //echo
				if (CheckAttackValid(x, z))
					Attack(x, z);
			}
			else
			{
				cout << "Format error." << endl << endl;
				DisplayHelp();
			}
			valid_type_found = true;
			break;
		case 'E':
		case 'e':
			cout << "Ending the turn." << endl << endl; //echo
			EndTurn();
			valid_type_found = true;
			break;
		case 'R':
		case 'r':
			cout << "Resigning." << endl << endl; //echo
			SetLose();
			valid_type_found = true;
			break;
		case 'B':
		case 'b':
			cout << "Printing the current board." << endl << endl; //echo
			PrintBoard();
			valid_type_found = true;
			break;
		case 'Q':
		case 'q':
			if (cin >> x)
			{
				cout << "Querying " << x << "." << endl << endl; //echo
				Query(x);
			}
			else
			{
				cout << "Format error." << endl << endl;
				DisplayHelp();
			}			
			valid_type_found = true;
			break;
		case 'O':
		case 'o':
			display_overheat_counts = !display_overheat_counts;
			cout << "Display of overheat counts switched " << (display_overheat_counts ? "on." : "off.") << endl << endl;
			break;
		/*case 'V':
		case 'v':
			cout << "Current State Evaluation: " << GetHeuristicEval() << endl << endl;
			break;*/ // this is only for testing, as the evaluation assumes end of turn state, which is not the case when querying
		case 'H':
		case 'h':
			cout << "Displaying command manual." << endl << endl; //echo
			DisplayHelp();
			valid_type_found = true;
			break;
		}
	}
}

void Player::DisplayHelp() const
{
	cout << "(Note that all numbering used below should be consistent to the numbering in the current board info, i.e. by the order of you leader, your minions, and then opponent minions, opponent leader, and finally your hand.)" << endl << endl;
	cout << "P x y z: play card x from hand at position y and target z, the positioning y is for the minion on the left (0 if the first one), and the target z should be specified with the numbering on current board, y and/or z are sometimes not used;" << endl;
	cout << "A x y: use your minion x to attack enemy leader/minion y, the ordering the same as they target in play card command;" << endl;
	cout << "E: end turn;" << endl;
	cout << "R: resign;" << endl;
	cout << "B: print board;" << endl;
	cout << "Q x: query details on leader/minion x, the ordering the same as they target in play card command;" << endl;
	cout << "O: switch on/off the display of overheat counts, currently " << (display_overheat_counts ? "on;" : "off;") << endl;
	cout << "H: help on commands." << endl << endl;
}

void Player::Query(int x) const
{
	if (x == 0)
		cout << DetailInfo() << endl;
	else if (x > 0 && x <= field.size())
		cout << field[x - 1]->DetailInfo() << endl;
	else if (x > field.size() && x <= field.size() + opponent->field.size())
		cout << opponent->field[x - field.size() - 1]->DetailInfo() << endl;
	else if (x == field.size() + opponent->field.size() + 1)
		cout << opponent->DetailInfo() << endl;
	else if (x > field.size() + opponent->field.size() + 1 && x <= field.size() + opponent->field.size() + hand.size() + 1)
		cout << hand[x - field.size() - opponent->field.size() - 2]->DetailInfo() << endl;
	else
		cout << "Invalid Target for Querying" << endl;
	cout << endl;
}

string Player::BriefInfo() const
{
	return leader->BriefInfo();
}

string Player::DetailInfo() const
{
	return leader->DetailInfo();
}

void Player::PrintBoard() const
{
	const Player *host, *guest;
	if (is_guest)
	{
		host = opponent;
		guest = this;
	}
	else
	{
		host = this;
		guest = opponent;
	}
	cout << endl;
	cout << guest->name << "\'s Side" << endl;
	cout << "================================" << endl;
	cout << "Opponent Deck Size: " << guest->deck.size() << endl;
	cout << "Opponent Hand Size: " << guest->hand.size() << endl;
	cout << "Opponent MP: " << guest->max_mp - guest->mp_loss << " of " << guest->max_mp << endl;
	cout << "--------------------------------" << endl;
	cout << "Opponent Leader:" << endl;
	cout << host->field.size() + guest->field.size() + 1 << " -- " << guest->BriefInfo() << endl;
	cout << "Opponent Minions:" << endl;
	for (int i = guest->field.size() - 1; i >= 0 ; i--)
		cout << i + host->field.size() + 1 << " -- " << guest->field[i]->BriefInfo() << endl;
	cout << "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" << endl;
	cout << "Your Minions:" << endl;
	for (int i = host->field.size() - 1; i >= 0; i--)
		cout << i + 1 << " -- " << host->field[i]->BriefInfo() << endl;
	cout << "Your Leader:" << endl;
	cout << 0 << " -- " << host->BriefInfo() << endl;
	cout << "--------------------------------" << endl;
	cout << "Your MP: " << host->max_mp - host->mp_loss << " of " << host->max_mp << endl;
	cout << "Your Hand: " << endl;
	for (int i = 0; i < host->hand.size(); i++)
		cout << i + host->field.size() + guest->field.size() + 2 << " -- " << host->hand[i]->BriefInfo() << endl;
	cout << "Your Deck Size: " << host->deck.size() << endl;
	cout << "================================" << endl;
	cout << host->name << "\'s Side" << endl << endl;
}

int Player::GetActualFieldSize() const
{
	return field.size() + field_size_adjust;
}

int Player::GetActualHandSize() const
{
	return hand.size() + hand_size_adjust;
}

int Player::GetActualDeckSize() const
{
	return deck.size() + deck_size_adjust;
}


/* Generator/Descriptor Section */


void IntersectRange(int& min_result, int& max_result, int min1, int max1, int min2, int max2)
{
	min_result = (min2 > min1 ? min2 : min1);
	max_result = (max2 < max1 ? max2 : max1);
}

void IntersectRangeInPlace(int& min_val, int& max_val, int other_min_val, int other_max_val)
{
	if (other_min_val > min_val)
		min_val = other_min_val;
	if (other_max_val < max_val)
		max_val = other_max_val;
}

void UnionRangeInPlace(int& min_val, int& max_val, int other_min_val, int other_max_val)
{
	if (other_min_val < min_val)
		min_val = other_min_val;
	if (other_max_val > max_val)
		max_val = other_max_val;
}


CondConfig::CondConfig(unsigned _flag, int _min_mp, int _max_mp, int _min_max_mp, int _max_max_mp, int _min_cost, int _max_cost, int _min_atk, int _max_atk, int _min_hp, int _max_hp, int _min_n_atks, int _max_n_atks)
	: flag(_flag), min_mp(_min_mp), max_mp(_max_mp), min_max_mp(_min_max_mp), max_max_mp(_max_max_mp), min_cost(_min_cost), max_cost(_max_cost), min_atk(_min_atk), max_atk(_max_atk), min_hp(_min_hp), max_hp(_max_hp), min_n_atks(_min_n_atks), max_n_atks(_max_n_atks)
{
}

CondConfig::CondConfig(unsigned _flag, int _min_cost, int _max_cost, int _min_atk, int _max_atk, int _min_hp, int _max_hp, int _min_n_atks, int _max_n_atks)
	: CondConfig(_flag, 0, 10, 0, 10, _min_cost, _max_cost, _min_atk, _max_atk, _min_hp, _max_hp, _min_n_atks, _max_n_atks)
{
}

CondConfig::CondConfig(unsigned _flag)
	: CondConfig(_flag, 0, 10, 0, 10, -9, 40, 0, 5)
{
	if (!(_flag & TARGET_IS_SPELL))
	{
		// if it is referring to a character and considers minions or only allowing minions then the upper bound for HP become lower
		if (_flag & TARGET_IS_MINION)
		{
			if (_flag & TARGET_IS_LEADER)
				max_hp = 20;
			else
				max_hp = 10;
		}
	}
}

CondConfig::CondConfig()
	: CondConfig(TARGET_TYPE_ANY, 0, 10, 0, 10, -9, 40, 0, 5)  // -9 is taking into consideration of on destroy (deathrattle) timing
{
}

CondConfig CondConfig::operator &= (const CondConfig& config)
{
	flag &= config.flag;
	IntersectRangeInPlace(min_mp, max_mp, config.min_mp, config.max_mp);
	IntersectRangeInPlace(min_max_mp, max_max_mp, config.min_max_mp, config.max_max_mp);
	IntersectRangeInPlace(min_cost, max_cost, config.min_cost, config.max_cost);
	IntersectRangeInPlace(min_atk, max_atk, config.min_atk, config.max_atk);
	IntersectRangeInPlace(min_hp, max_hp, config.min_hp, config.max_hp);
	IntersectRangeInPlace(min_n_atks, max_n_atks, config.min_n_atks, config.max_n_atks);

	return *this;
}

CondConfig CondConfig::operator &= (unsigned flag)
{
	this->flag &= flag;

	return *this;
}

CondConfig CondConfig::operator |= (const CondConfig & config)
{
	UnionRangeInPlace(min_mp, max_mp, config.min_mp, config.max_mp);
	UnionRangeInPlace(min_max_mp, max_max_mp, config.min_max_mp, config.max_max_mp);
	UnionRangeInPlace(min_cost, max_cost, config.min_cost, config.max_cost);
	UnionRangeInPlace(min_atk, max_atk, config.min_atk, config.max_atk);
	UnionRangeInPlace(min_hp, max_hp, config.min_hp, config.max_hp);
	UnionRangeInPlace(min_n_atks, max_n_atks, config.min_n_atks, config.max_n_atks);

	return *this;
}

CondConfig CondConfig::operator |= (unsigned flag)
{
	this->flag |= flag;

	return *this;
}

unsigned CondConfig::operator&(unsigned mask) const
{
	return flag & mask;
}

unsigned CondConfig::operator|(unsigned mask) const
{
	return flag | mask;
}

CondConfig GetInitConfigFromCard(const Card* card)
{
	unsigned card_pos_flag = TARGET_ANY_POS_TYPE;
	unsigned card_type_flag = TARGET_ANY_CARD_TYPE;
	unsigned minion_type_flag = TARGET_TYPE_NOTHING;

	switch (card->card_type)
	{
	case LEADER_CARD:
		card_type_flag = TARGET_IS_LEADER;
		break;
	case MINION_CARD:
		card_type_flag = TARGET_IS_MINION;
		switch (card->minion_type)
		{
		case BEAST_MINION:
			minion_type_flag = TARGET_IS_BEAST;
			break;
		case DRAGON_MINION:
			minion_type_flag = TARGET_IS_DRAGON;
			break;
		case DEMON_MINION:
			minion_type_flag = TARGET_IS_DEMON;
			break;
		}
		break;
	case SPELL_CARD:
		card_type_flag = TARGET_IS_SPELL;
		card_pos_flag = TARGET_POS_HAND_OR_DECK;
		break;
	}

	// card position
	unsigned flag = card_pos_flag | card_type_flag | minion_type_flag;

	return CondConfig(flag, card->mana, card->mana, card->atk, card->atk, card->max_hp, card->max_hp, card->max_n_atks, card->max_n_atks);
}

CondConfig ExtractEffectIndependentConfig(const CondConfig& config)
{
	// remove the position flags that are effect dependent
	unsigned correct_pos_flag = (!(config & TARGET_ANY_CHAR) ? TARGET_POS_HAND_OR_DECK : TARGET_ANY_POS_TYPE);

	return CondConfig(config.flag | correct_pos_flag, config.min_mp, config.max_mp, config.min_max_mp, config.max_max_mp, config.min_cost, config.max_cost, config.min_atk, config.max_atk, config.min_hp, config.max_hp, config.min_n_atks, config.max_n_atks);
}

CondConfig GetDefaultInitConfig()
{
	return CondConfig(TARGET_ANY_POS_TYPE | TARGET_ANY_CARD_ALLE_MINION_TYPE);
}

CondConfig GetDefaultConfig()
{
	return CondConfig();
}

CondConfig GetFlagConfig(unsigned flag)
{
	return CondConfig(flag);
}

CondConfig GetMpConfig(int min_mp, int max_mp)
{
	return CondConfig(TARGET_TYPE_ANY, min_mp, max_mp, min_mp, 10, 0, 10, 0, 10, -9, 40, 0, 5);
}

CondConfig GetMaxMpConfig(int min_max_mp, int max_max_mp)
{
	return CondConfig(TARGET_TYPE_ANY, 0, max_max_mp, min_max_mp, max_max_mp, 0, 10, 0, 10, -9, 40, 0, 5);
}

CondConfig GetCostConfig(unsigned flag, int min_cost, int max_cost)
{
	return CondConfig(flag, min_cost, max_cost, 0, 10, -9, 40, 0, 5);
}

CondConfig GetAtkConfig(unsigned flag, int min_atk, int max_atk)
{
	return  CondConfig(flag, 0, 10, min_atk, max_atk, -9, 40, 0, 5);
}

CondConfig GetHpConfig(unsigned flag, int min_hp, int max_hp)
{
	return CondConfig(flag, 0, 10, 0, 10, min_hp, max_hp, 0, 5);
}

CondConfig GetAtkTimesConfig(unsigned flag, int min_n_atks, int max_n_atks)
{
	return CondConfig(flag, 0, 10, 0, 10, -9, 40, min_n_atks, max_n_atks);
}


bool display_overheat_counts = false;


string MinionTypeDescription(int type)
{
	switch (type)
	{
	case BEAST_MINION:
		return "Beast";
	case DRAGON_MINION:
		return "Dragon";
	case DEMON_MINION:
		return "Demon";
	}

	return "";
}

string AttributeDescriptionInline(bool is_charge, bool is_taunt, bool is_stealth, bool is_untargetable, bool is_shielded, bool is_poisonous, bool is_lifesteal)
{
	string desc =
		(is_charge ? string("Charge, ") : string("")) // the string() is needed at least for the first item otherwise it would have trouble figuring out the type (wouldn't compile)
		+ (is_taunt ? string("Taunt, ") : string(""))
		+ (is_stealth ? string("Stealth, ") : string(""))
		+ (is_untargetable ? string("Untargetable, ") : string(""))
		+ (is_shielded ? string("Shielded, ") : string(""))
		+ (is_poisonous ? string("Poisonous, ") : string(""))
		+ (is_lifesteal ? string("Lifesteal, ") : string(""));
	if (desc.length() > 1) // remove the last space and comma if non-empty
	{
		desc.pop_back();
		desc.pop_back();
		desc = " with " + desc;
	}
	return desc; // add a leading space
}

string AttributeDescriptionBrief(bool is_charge, bool is_taunt, bool is_stealth, bool is_untargetable, bool is_shielded, bool is_poisonous, bool is_lifesteal)
{
	string desc = 
		(is_charge ? string("Charge. ") : string("")) // the string() is needed at least for the first item otherwise it would have trouble figuring out the type (wouldn't compile)
		+ (is_taunt ? string("Taunt. ") : string(""))
		+ (is_stealth ? string("Stealth. ") : string(""))
		+ (is_untargetable ? string("Untargetable. ") : string(""))
		+ (is_shielded ? string("Shielded. ") : string(""))
		+ (is_poisonous ? string("Poisonous. ") : string(""))
		+ (is_lifesteal ? string("Lifesteal. ") : string(""));
	if (desc.length() > 0) // remove the last space if non-empty
		desc.pop_back();
	return desc;
}

string AttributeDescriptionDetail(bool is_charge, bool is_taunt, bool is_stealth, bool is_untargetable, bool is_shielded, bool is_poisonous, bool is_lifesteal, int indent_size)
{
	return (is_charge ? string("Charge.\n") + RepeatSpace(indent_size) : string("")) // the string() is needed at least for the first item otherwise it would have trouble figuring out the type (wouldn't compile)
		+ (is_taunt ? string("Taunt.\n") + RepeatSpace(indent_size) : string(""))
		+ (is_stealth ? string("Stealth.\n") + RepeatSpace(indent_size) : string(""))
		+ (is_untargetable ? string("Untargetable (Cannot be targeted by spells or battlecries).\n") + RepeatSpace(indent_size) : (""))
		+ (is_shielded ? string("Shielded (Divine Shield).\n") + RepeatSpace(indent_size) : string(""))
		+ (is_poisonous ? string("Poisonous.\n") + RepeatSpace(indent_size) : string(""))
		+ (is_lifesteal ? string("Lifesteal.\n") + RepeatSpace(indent_size) : string(""));
}


/* Simulator Section */

int GetGiglRandInt()
{
	return GetRandInt();
}

int GetGiglRandInt(int n)
{
	return GetRandInt(n);
}

double GetGiglRandFloat()
{
	return GetRandFloat();
}

double GetGiglRandFloat(double max_val)
{
	return GetRandFloat(max_val);
}

vector<int> CreateRandomSelection(int n, int k)
{
	int* a = new int[n];
	for (int i = 0; i < n; i++)
		a[i] = i;
	RandShuffle(a, n, k);
	vector<int> selected_indices(a+n-k, a+n); // note: the ending reference should be just outside the range
	delete [] a;

	return selected_indices;
}

vector<int> CreateRandomSelectionSorted(int n, int k)
{
	vector<int> selected_list = CreateRandomSelection(n, k);
	sort(selected_list.begin(), selected_list.end());
	return selected_list;
}

Card* GenerateSingleCard(int seed)
{
	return GenerateCard(seed);
}

string GetCardBrief(Card* card)
{
	return card->BriefInfo();
}

string GetCardDetail(Card* card)
{
	return card->DetailInfo();
}

vector<Card*> GenerateRandDeck(int n, int seed)
{
	RandInit(seed);

	vector<Card*> deck(n);
	for (int i = 0; i < n; i++)
	{
		seed = GetRandInt();
		deck[i] = GenerateSingleCard(seed);
		// deck[i] = GenerateSingleCard(1); // for testing
		// deck[i] = CreateTestCard(i % 2); // for testing
	}

	return deck;
}

vector<int> GenerateCardSetSeeds(int n, int seed)
{
	RandInit(seed);

	vector<int> seed_set(n);
	for (int i = 0; i < n; i++)
		seed_set[i] = GetRandInt();

	// remove duplicates (so it is easier for checking # of overlapped cards between deck through seeds), should rarely actually happen, but just in case, will also make the seeds be sorted (increaing) at the same time
	bool no_duplicate;
	do
	{
		no_duplicate = true;
		sort(seed_set.begin(), seed_set.end());
		for (int i = 1; i < n; i++)
		{
			if (seed_set[i] == seed_set[i - 1])
			{
				no_duplicate = false;
				int dup = seed_set[i - 1];
				seed_set[i] = GetRandInt();
				while(seed_set[i] == dup)
					seed_set[i] = GetRandInt();
				for (i++; i < n; i++)
				{
					if (seed_set[i] == dup)
					{
						seed_set[i] = GetRandInt();
						while (seed_set[i] == dup)
							seed_set[i] = GetRandInt();
					}
					else
						break;
				}
			}
		}
	}
	while(!no_duplicate);

	return seed_set;
}

vector<Card*> GenerateRandDeckFromSeedList(const vector<int>& seeds)
{
	int n = seeds.size();
	vector<Card*> deck(n);
	for (int i = 0; i < n; i++)
		deck[i] = GenerateSingleCard(seeds[i]);

	return deck;
}

void InitMatch(const vector<int>& seed_list, vector<int>& deck_a_indices, vector<int>& deck_b_indices, vector<int>& deck_a_seeds, vector<int>& deck_b_seeds)
{
	int seed = GetRandInt();
	RandInit(seed);
	cout << "Match seed: " << seed << ". ";

	int size_a = deck_a_indices.size();
	int size_b = deck_b_indices.size();

	// Shuffle
	RandShuffle(deck_a_indices.data(), size_a);
	RandShuffle(deck_b_indices.data(), size_b);
	
	// index to seeds
	for (int k = 0; k < size_a; k++)
		deck_a_seeds[k] = seed_list[deck_a_indices[k]];
	for (int k = 0; k < size_b; k++)
		deck_b_seeds[k] = seed_list[deck_b_indices[k]];
}

void DecidePlayOrder(Player* player1, Player* player2, Player*& first_player, Player*& second_player)
{
	if (GetRandInt() % 2)
	{
		first_player = player1;
		second_player = player2;
	}
	else
	{
		first_player = player2;
		second_player = player1;
	}

	cout << first_player->name << " goes first." << endl << endl;
}

void DeleteCard(Card * card)
{
	delete card;
}


DeferredEvent::DeferredEvent(Card* _card, bool _start_of_batch) : card(_card), is_start_of_batch(_start_of_batch)
{
}

DestroyEvent::DestroyEvent(Card* _card, bool _start_of_batch) : DeferredEvent(_card, _start_of_batch)
{
}

void DestroyEvent::Process(Player* curr_player)
{
	if (card == curr_player->leader)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!curr_player->is_exploration)
			cout << curr_player->name << "\'s leader " << card->name << " destroyed." << endl << endl;
		#endif
		curr_player->SetLose();
	}
	else if (card == curr_player->opponent->leader)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!curr_player->is_exploration)
			cout << curr_player->opponent->name << "\'s leader " << card->name << " destroyed." << endl << endl;
		#endif
		curr_player->opponent->SetLose();
	}
	else
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!curr_player->is_exploration)
			cout << card->owner->name << "\'s minion " << card->name << " destroyed." << endl << endl;
		#endif
		card->Destroy();
	}
}

CastEvent::CastEvent(Card* _card, bool _start_of_batch) : DeferredEvent(_card, _start_of_batch)
{
}

void CastEvent::Process(Player* curr_player)
{
	// do nothing
}

DiscardEvent::DiscardEvent(Card* _card, bool _start_of_batch) : DeferredEvent(_card, _start_of_batch)
{
}

void DiscardEvent::Process(Player* curr_player)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!curr_player->is_exploration)
		cout << card->owner->name << "\'s " << card->name << " discarded." << endl << endl;
	#endif
	card->Discard();
}

FieldSummonEvent::FieldSummonEvent(Card* _card, bool _start_of_batch, Player* _owner) : DeferredEvent(_card, _start_of_batch), owner(_owner)
{
}

void FieldSummonEvent::Process(Player* curr_player)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!curr_player->is_exploration)
		cout << card->owner->name << "\'s " << card->name << " summoned to " << owner->name << "\'s field." << endl << endl;
	#endif
	owner->SummonToField(card);
	owner->field_size_adjust--;
}

HandPutEvent::HandPutEvent(Card* _card, bool _start_of_batch, Player* _owner) : DeferredEvent(_card, _start_of_batch), owner(_owner)
{
}

void HandPutEvent::Process(Player* curr_player)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!curr_player->is_exploration)
		cout << card->owner->name << "\'s " << card->name << " put to " << owner->name << "\'s hand." << endl << endl;
	#endif
	owner->PutToHand(card);
	owner->hand_size_adjust--;
}

DeckShuffleEvent::DeckShuffleEvent(Card* _card, bool _start_of_batch, Player* _owner) : DeferredEvent(_card, _start_of_batch), owner(_owner)
{
}

void DeckShuffleEvent::Process(Player* curr_player)
{
	#ifndef SUPPRESS_ALL_MSG
	if (!curr_player->is_exploration)
		cout << card->owner->name << "\'s " << card->name << " shuffled to " << owner->name << "\'s deck." << endl << endl;
	#endif
	owner->ShuffleToDeck(card);
	owner->deck_size_adjust--;
}

CardTransformEvent::CardTransformEvent(Card* _card, bool _start_of_batch, Card* _replacement) : DeferredEvent(_card, _start_of_batch), replacement(_replacement)
{
}

void CardTransformEvent::Process(Player* curr_player)
{
	// well many of the following could be put into the FlagCardTransform function but its not much of a difference for now
	#ifndef SUPPRESS_ALL_MSG
	if (!curr_player->is_exploration)
		cout << card->owner->name << "\'s " << card->name << " transformed to " << replacement->name << "." << endl << endl;
	#endif
	replacement->card_pos = card->card_pos;
	replacement->owner = card->owner;
	replacement->opponent = card->opponent;
	card->replacement = replacement; // not actually replacing yet, leave it to clear corpse
}

CardResetEvent::CardResetEvent(Card* _card, bool _start_of_batch) : DeferredEvent(_card, _start_of_batch)
{
}

void CardResetEvent::Process(Player* curr_player)
{
	// do nothing
}


/* AI Section */


ActionEntity::ActionEntity()
{
}

PlayAction::PlayAction(int _src, int _pos, int _des) : src(_src), pos(_pos), des(_des)
{
}

bool PlayAction::CheckValid(Player* player) const
{
	int tmp_des = des; // CheckPlayValid may modify the destination to -1 if it is untargeted, this is only meaningful for human console input, AI will check if it is Targeted before hand
	return player->CheckPlayValid(src, pos, tmp_des);
}

void PlayAction::PerformAction(Player* player) const
{
	player->Play(src, pos, des);
}

AttackAction::AttackAction(int _src, int _des) : src(_src), des(_des)
{
}

bool AttackAction::CheckValid(Player* player) const
{
	return player->CheckAttackValid(src, des);
}

void AttackAction::PerformAction(Player* player) const
{
	player->Attack(src, des);
}

EndTurnAction::EndTurnAction()
{
}

bool EndTurnAction::CheckValid(Player* player) const
{
	return true;
}

void EndTurnAction::PerformAction(Player* player) const
{
	player->EndTurn();
}

ActionSetEntity::ActionSetEntity() : action_set()
{
}

ActionSetEntity::~ActionSetEntity()
{
	for (auto it = action_set.begin(); it != action_set.end(); it++)
		delete (*it);
}

PlayActionSet::PlayActionSet(int _card_index) : card_index(_card_index)
{
}

int PlayActionSet::CreateValidSet(Player* player)
{
	if (card_index <= player->field.size() + player->opponent->field.size() + 1 || card_index > player->field.size() + player->opponent->field.size() + player->hand.size() + 1)
		return 0;

	int x = card_index - (player->field.size() + player->opponent->field.size() + 2);
	Card* tmp_card = player->hand[x];

	if (tmp_card->card_type == SPELL_CARD)
	{
		if (tmp_card->isTargetedAtPlay(card_index, -1))
		{
			for (int i = 0; i <= player->field.size() + player->opponent->field.size() + player->hand.size() + 1; i++)
			{
				PlayAction* tmp_action = new PlayAction(card_index, -1, i);
				if (tmp_action->CheckValid(player))
					action_set.push_back(tmp_action);
				else
					delete tmp_action;
			}
		}
		else
		{
			PlayAction* tmp_action = new PlayAction(card_index, -1, -1);
			if (tmp_action->CheckValid(player))
				action_set.push_back(tmp_action);
			else
				delete tmp_action;
		}
	}
	else
	{
		for (int j = 0; j <= player->field.size(); j++)
		{

			if (tmp_card->isTargetedAtPlay(card_index, j))
			{
				for (int i = 0; i <= player->field.size() + player->opponent->field.size() + player->hand.size() + 1; i++)
				{
					PlayAction* tmp_action = new PlayAction(card_index, j, i);
					if (tmp_action->CheckValid(player))
						action_set.push_back(tmp_action);
					else
						delete tmp_action;
				}
			}
			else
			{
				PlayAction* tmp_action = new PlayAction(card_index, j, -1);
				if (tmp_action->CheckValid(player))
					action_set.push_back(tmp_action);
				else
					delete tmp_action;
			}
		}
	}

	return action_set.size();
}

int PlayActionSet::RecheckValidity(Player* player)
{
	// well there are more efficient algorithms to delete multiple entries but we expect this to rarely happen
	for (int i = action_set.size() - 1; i >= 0; i--) // note erasing when looping with iterators is more error prone
	{
		if (!action_set[i]->CheckValid(player))
			action_set.erase(action_set.begin() + i);
	}

	return action_set.size();
}

void PlayActionSet::PerformRandomAction(Player* player) const
{
	int i = GetRandInt(action_set.size());
	action_set[i]->PerformAction(player);
}

AttackActionSet::AttackActionSet(int _card_index) : card_index(_card_index)
{
}

int AttackActionSet::CreateValidSet(Player* player)
{
	if (card_index < 0 || card_index > player->field.size())
		return 0;

	for (int i = player->field.size() + 1; i <= player->field.size() + player->opponent->field.size() + 1; i++)
	{
		AttackAction* tmp_action = new AttackAction(card_index, i);
		if (tmp_action->CheckValid(player))
			action_set.push_back(tmp_action);
		else
			delete tmp_action;
	}

	return action_set.size();
}

int AttackActionSet::RecheckValidity(Player* player)
{
	// well there are more efficient algorithms to delete multiple entries but we expect this to rarely happen
	for (int i = action_set.size() - 1; i >= 0; i--) // note erasing when looping with iterators is more error prone 
	{
		if (!action_set[i]->CheckValid(player))
			action_set.erase(action_set.begin() + i);
	}

	return action_set.size();
}

void AttackActionSet::PerformRandomAction(Player* player) const
{
	int i = GetRandInt(action_set.size());
	action_set[i]->PerformAction(player);
}

EndTurnActionSet::EndTurnActionSet()
{
}

int EndTurnActionSet::CreateValidSet(Player* player)
{
	action_set.push_back(new EndTurnAction());
	return 1;
}

int EndTurnActionSet::RecheckValidity(Player* player)
{
	return 1;
}

void EndTurnActionSet::PerformRandomAction(Player* player) const
{
	action_set[0]->PerformAction(player);
}


KnowledgeActionNode::KnowledgeActionNode(const ActionEntity * _action) : num_visits(0), sum_eval(0.0), ave_eval(0.0), action(_action)
{
}

const ActionEntity* KnowledgeActionNode::GetAction() const
{
	return action;
}

double KnowledgeActionNode::TestAction(Player* player)
{
	action->PerformAction(player);
	if (player->is_turn_active)
		player->TakeRandomAIInputs();
	num_visits++;
	double tmp_eval = player->GetHeuristicEval();
	sum_eval += tmp_eval;
	ave_eval = sum_eval / (double)num_visits;
	return tmp_eval;
}

KnowledgeOptionNode::KnowledgeOptionNode(const ActionSetEntity* _action_set) : num_visits(0), sum_eval(0.0), ave_eval(0.0), action_nodes()
{
	for (auto it = _action_set->action_set.begin(); it != _action_set->action_set.end(); it++)
		action_nodes.push_back(new KnowledgeActionNode(*it));
}

KnowledgeOptionNode::~KnowledgeOptionNode()
{
	for (auto it = action_nodes.begin(); it != action_nodes.end(); it++)
		delete (*it);
}

const KnowledgeActionNode* KnowledgeOptionNode::GetOptimalActionNode() const
{
	double best_eval = -1e10;
	const KnowledgeActionNode* best_node = nullptr;

	for (auto it = action_nodes.begin(); it != action_nodes.end(); it++)
	{
		const KnowledgeActionNode* tmp_node = (*it);
		double tmp_eval = tmp_node->ave_eval;
		if (tmp_eval > best_eval)
		{
			best_eval = tmp_eval;
			best_node = tmp_node;
		}
	}

	return best_node;
}

double KnowledgeOptionNode::TestAction(Player* player)
{
	KnowledgeActionNode* selected_node = nullptr;

	// first see if there is any unvisited child
	auto it = action_nodes.begin();
	while (it != action_nodes.end() && (*it)->num_visits > 0)
		it++;
	// if not then it should be at the "end()" at this point, we do UCB-1 for a mult-armed bandit choice; if so then the "it" should be pointing to the first unvisited child at this point, we choose that node
	if (it == action_nodes.end())
	{
		double max_priority_weight = -1e10;
		double two_ln_visits = 2.0 * log(num_visits);
		for (it = action_nodes.begin(); it != action_nodes.end(); it++)
		{
			KnowledgeActionNode* tmp_node = (*it);
			int tmp_visits = tmp_node->num_visits;
			if (tmp_visits == 0)
			{
				selected_node = tmp_node;
				break;
			}

			double tmp_eval = tmp_node->ave_eval;
			double tmp_weight = tmp_eval + 2.0 * sqrt(two_ln_visits / (double)tmp_visits); // UCB-1, the 2.0 is for scalling up for range -1 ~ 1 as opposed to 0 ~ 1
			if (tmp_weight > max_priority_weight)
			{
				max_priority_weight = tmp_weight;
				selected_node = tmp_node;
			}
		}
	}
	else
		selected_node = (*it);

	num_visits++;
	double tmp_eval = selected_node->TestAction(player);
	sum_eval += tmp_eval;
	ave_eval = sum_eval / (double)num_visits;
	return tmp_eval;
}

KnowledgeState::KnowledgeState(Player* _player, queue<DeferredEvent*>& event_queue, PtrRedirMap& redir_map) : num_visits(0), option_nodes(), num_tests_scaling(_player->ai_level), orig_player(_player), ally_player(_player->CreateKnowledgeCopy(COPY_ALLY, event_queue, redir_map)), oppo_player(_player->opponent->CreateKnowledgeCopy(COPY_OPPO, event_queue, redir_map))
{
	ally_player->opponent = oppo_player;
	oppo_player->opponent = ally_player;
	ally_player->SetAllCardAfflications();
	oppo_player->SetAllCardAfflications();

	vector<ActionSetEntity*> option_set = _player->GetOptionSet();

	// re-check if each action is still in the knowledge copy, if not remove (this is a relatively native solution, it guarentees not broken by only considering actions that are valid in both truth state and knowledge state)
	num_actions = 0;
	// well there are more efficient algorithms to delete multiple entries but we expect this to rarely happen
	for (int i = option_set.size() - 1; i >= 0; i--) // note erasing when looping with iterators is more error prone
	{
		int tmp_num_actions = option_set[i]->RecheckValidity(ally_player);
		if (tmp_num_actions > 0)
			num_actions += tmp_num_actions;
		else
			option_set.erase(option_set.begin() + i);
	}

	for (auto it = option_set.begin(); it != option_set.end(); it++)
		option_nodes.push_back(new KnowledgeOptionNode(*it));
}

KnowledgeState::~KnowledgeState()
{
	for (auto it = option_nodes.begin(); it != option_nodes.end(); it++)
		delete (*it);

	// note: don't delete the orig_player as it is managed in the actual game
	delete ally_player;
	delete oppo_player;
}

const ActionEntity* KnowledgeState::GetOptimalAction() const
{
	double best_eval = -1e10;
	const ActionEntity* best_action = nullptr;
	
	for (auto it = option_nodes.begin(); it != option_nodes.end(); it++)
	{
		const KnowledgeActionNode* tmp_best_node = (*it)->GetOptimalActionNode();
		double tmp_best_eval = tmp_best_node->ave_eval;
		if (tmp_best_eval > best_eval)
		{
			best_eval = tmp_best_eval;
			best_action = tmp_best_node->GetAction();
		}
	}

	return best_action;
}

double KnowledgeState::TestAction(Player* player)
{
	KnowledgeOptionNode* selected_node = nullptr;

	// first see if there is any unvisited child
	auto it = option_nodes.begin();
	while (it != option_nodes.end() && (*it)->num_visits > 0)
		it++;
	// if not then it should be at the "end()" at this point, we do UCB-1 for a mult-armed bandit choice; if so then the "it" should be pointing to the first unvisited child at this point, we choose that node
	if (it == option_nodes.end())
	{
		double max_priority_weight = -1e10;
		double two_ln_visits = 2.0 * log(num_visits);
		for (it = option_nodes.begin(); it != option_nodes.end(); it++)
		{
			KnowledgeOptionNode* tmp_node = (*it);
			int tmp_visits = tmp_node->num_visits;
			if (tmp_visits == 0)
			{
				selected_node = tmp_node;
				break;
			}

			double tmp_eval = tmp_node->ave_eval;
			double tmp_weight = tmp_eval + 2.0 * sqrt(two_ln_visits / (double)tmp_visits); // UCB-1, the 2.0 is for scalling up for range -1 ~ 1 as opposed to 0 ~ 1
			if (tmp_weight > max_priority_weight)
			{
				max_priority_weight = tmp_weight;
				selected_node = tmp_node;
			}
		}
	}
	else
		selected_node = (*it);

	num_visits++;
	double tmp_eval = selected_node->TestAction(player);
	return tmp_eval;
}

void KnowledgeState::PerformAction()
{
	// search/test
	int total_num_tests = (num_actions - 1) * num_tests_scaling; // subtract one because if there were only one action there is no need to test
	for (int i = 0; i < total_num_tests; i++)
	{
		queue<DeferredEvent*> event_queue;
		PtrRedirMap redir_map;
		Player* ally_copy = ally_player->CreateKnowledgeCopy(COPY_EXACT, event_queue, redir_map);
		Player* oppo_copy = oppo_player->CreateKnowledgeCopy(COPY_EXACT, event_queue, redir_map);
		ally_copy->opponent = oppo_copy;
		oppo_copy->opponent = ally_copy;
		ally_copy->SetAllCardAfflications();
		oppo_copy->SetAllCardAfflications();
		TestAction(ally_copy);
		while (!event_queue.empty())
		{
			delete event_queue.front(); // note: this is not deleting the actual card but the entity for flagging
			event_queue.pop();
		}
		delete ally_copy;
		delete oppo_copy;
	}

	// execute the optimal action
	GetOptimalAction()->PerformAction(orig_player);
}


/* Machine Learning Section */


NodeRep::NodeRep(int _choice, const vector<double>& _term_info)
	: choice(_choice), term_info(_term_info)
{
}

string NodeRep::GetPrintVersion() const
{
	int term_len = term_info.size();
	string tmp_string = IntToStr(choice) + ", " + IntToStr(term_len) + ": ";
	for (int i = 0; i < term_len; i++)
		tmp_string += FloatToStr(term_info[i]) + " ";
	tmp_string += "; ";

	return tmp_string;
}


NodeRep mkNodeRep(int choice, const vector<double>& term_info)
{
	return NodeRep(choice, term_info);
}

NodeRep mkNodeRep(int choice)
{
	return NodeRep(choice, vector<double>{});
}


double NormalizeCode(double val, double min_val, double max_val)
{
	return (2* val - max_val - min_val) / (max_val - min_val);
}

void GetCardRepsFromSeeds(const vector<int>& seed_list, vector<CardRep>& card_reps)
{
	int p = seed_list.size();

	card_reps.resize(p);
	for (int i = 0; i < p; i++)
	{
		Card* tmp_card = GenerateSingleCard(seed_list[i]);
		tmp_card->FillRep(card_reps[i]);
	}
}


const int Card_Train_Batch_Size = 100;
const int Card_Validate_Batch_Size = 500; // not actually used in this version
const int Card_Num_Epochs = 300; // this means maximum number of epochs, if with early stopping
const double Dropout_Rate = 0.2; // this is the probability each applied node is dropped out (i.e. not retained)

torch::Tensor CreateZerosTensor(size_t size)
{
	return torch::zeros({size}, torch::kDouble);
}

torch::Tensor CreateSingleValTensor(double val)
{
	return torch::full({1}, val, torch::kDouble);
}

torch::Tensor CreateOnehotTensor(int choice, size_t size)
{
	vector<double> tmp_vect(size, 0.0);
	tmp_vect[choice] = 1.0;
	return torch::from_blob(tmp_vect.data(), {size}, torch::kDouble).clone();
}

int GetModelSize(const torch::nn::Module* model)
{
	int param_count = 0;
	for (const auto& p : model->parameters())
		param_count += p.numel();
	
	return param_count;
}

const int Hidden_Size_1 = 16; // mutable
const int Hidden_Size_2 = 4; // mutable
const int Alle_Cond_Size = 3;
const int Card_Root_Size = 64; // mutable
const int Attack_Times_Size = 1;
const int Minion_Type_Size = 3;
const int Attribute_Size = 7;
const int Damage_Attribute_Size = 2;
const int Special_Effects_Size = 64; // mutable
const int Single_Effect_Size = 32; // mutable
const int Targeted_Play_Eff_Size = Single_Effect_Size + 3;
const int Other_Eff_Size = Single_Effect_Size + Alle_Cond_Size + 6;
const int Effect_Seq_Size = 64; // mutable
const int Base_Targeted_Eff_Size = 48; // mutable
const int Base_Untargeted_Eff_Size = 64; // mutable
const int Cond_Size = 16; // mutable
const int Sub_Cond_Size = 16; // mutable
const int Char_Type_Cond_Size = 5;
const int Card_Type_Cond_Size = 7;
const int Card_Pos_Cond_Size = 3;
const int Attr_Cond_Size = 7;
const int Stat_Cond_Variant_Size = 3;
const int Stat_Cond_Size = 4 + Stat_Cond_Variant_Size;
const int Eff_Utility_Size = 24; // mutable; part of the rules from BaseTargtedEff
const int Destination_Size = 6 + Alle_Cond_Size;
const int New_Card_Variant_Size = 6 + 1 + Card_Root_Size;

CardNet::CardNet() :
	hidden_to_out(Hidden_Size_2, 1),
	hidden_1_to_hidden_2(Hidden_Size_1, Hidden_Size_2),
	root_to_hidden(Card_Root_Size, Hidden_Size_1),
	card_root_layer(3 + 3 + Attack_Times_Size + Minion_Type_Size + Attribute_Size + Special_Effects_Size, Card_Root_Size), 
	special_effects_layer(Targeted_Play_Eff_Size + Effect_Seq_Size, Special_Effects_Size),
	cons_other_effs_layer(Other_Eff_Size + Effect_Seq_Size, Effect_Seq_Size), 
	targeted_eff_layer(3 + Base_Targeted_Eff_Size + 2 * Cond_Size, Single_Effect_Size),
	untargeted_eff_layer(3 + Base_Untargeted_Eff_Size + Cond_Size, Single_Effect_Size),
	target_cond_layer(2 + Sub_Cond_Size, Cond_Size), 
	char_target_cond_layer(Alle_Cond_Size + Char_Type_Cond_Size + Attr_Cond_Size + Stat_Cond_Size, Sub_Cond_Size), 
	card_target_cond_layer(Card_Pos_Cond_Size + Alle_Cond_Size + Card_Type_Cond_Size + Attr_Cond_Size + Stat_Cond_Size, Sub_Cond_Size),
	inde_cond_layer(5 + Sub_Cond_Size, Cond_Size),
	leader_cond_layer(Alle_Cond_Size + Attr_Cond_Size + Stat_Cond_Size, Sub_Cond_Size),
	mp_or_max_cond_layer(Alle_Cond_Size + Stat_Cond_Variant_Size, Sub_Cond_Size),
	base_targeted_eff_layer(26 + 3 + Eff_Utility_Size, Base_Targeted_Eff_Size),
	damage_eff_layer(Damage_Attribute_Size, Eff_Utility_Size),
	move_or_copy_eff_layer(Destination_Size, Eff_Utility_Size),
	transform_eff_layer(New_Card_Variant_Size, Eff_Utility_Size),
	give_effects_eff_layer(Special_Effects_Size, Eff_Utility_Size),
	base_untargeted_eff_layer(9 + 1 + Base_Targeted_Eff_Size + Cond_Size, Base_Untargeted_Eff_Size),
	alle_to_cond_layer(Alle_Cond_Size, Cond_Size),
	new_eff_layer(Destination_Size + New_Card_Variant_Size, Base_Targeted_Eff_Size)
{
	register_module("hidden_to_out", hidden_to_out);
	register_module("hidden_1_to_hidden_2", hidden_1_to_hidden_2);
	register_module("root_to_hidden", root_to_hidden);
	register_module("card_root_layer", card_root_layer);
	register_module("special_effects_layer", special_effects_layer);
	register_module("cons_other_effs_layer", cons_other_effs_layer);
	register_module("targeted_eff_layer", targeted_eff_layer);
	register_module("untargeted_eff_layer", untargeted_eff_layer);
	register_module("target_cond_layer", target_cond_layer);
	register_module("char_target_cond_layer", char_target_cond_layer);
	register_module("card_target_cond_layer", card_target_cond_layer);
	register_module("inde_cond_layer", inde_cond_layer);
	register_module("leader_cond_layer", leader_cond_layer);
	register_module("mp_or_max_cond_layer", mp_or_max_cond_layer);
	register_module("base_targeted_eff_layer", base_targeted_eff_layer);
	register_module("damage_eff_layer", damage_eff_layer);
	register_module("move_or_copy_eff_layer", move_or_copy_eff_layer);
	register_module("transform_eff_layer", transform_eff_layer);
	register_module("give_effects_eff_layer", give_effects_eff_layer);
	register_module("base_untargeted_eff_layer", base_untargeted_eff_layer);
	register_module("alle_to_cond_layer", alle_to_cond_layer);
	register_module("new_eff_layer", new_eff_layer);	
}

torch::Tensor CardNet::forward_out(const torch::Tensor& root_code)
{
        torch::Tensor hidden_1 = torch::relu(root_to_hidden->forward(root_code)); // root_code is already after dropout
	torch::Tensor dropout_hidden_1 = torch::dropout(hidden_1, Dropout_Rate, is_training());
	torch::Tensor hidden_2 = torch::relu(hidden_1_to_hidden_2->forward(dropout_hidden_1));
	torch::Tensor dropout_hidden_2 = torch::dropout(hidden_2, Dropout_Rate, is_training());
        return torch::sigmoid(hidden_to_out->forward(dropout_hidden_2));
}

#define CHOICE_LEADER_CARD 0
#define CHOICE_MINION_CARD 1
#define CHOICE_SPELL_CARD 2
torch::Tensor CardNet::forward_card_root(NodeRep*& rep)
{
	const double* term_info = rep->term_info.data();
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 3);
	torch::Tensor cost_code;
	torch::Tensor attack_code;
	torch::Tensor hp_code;
	torch::Tensor attack_times_code;
	torch::Tensor minion_type_code;
	torch::Tensor attributes_code;
	torch::Tensor effects_code;
	switch(choice)
	{
	case CHOICE_LEADER_CARD:
		{
			cost_code = CreateSingleValTensor(term_info[0]);
			attack_code = CreateSingleValTensor(term_info[1]);
			hp_code = CreateSingleValTensor(term_info[2]);
			attack_times_code = forward_attack_times(rep); // note: the pointer will be incremented inside (similar below)
			minion_type_code = CreateZerosTensor(Minion_Type_Size);
			attributes_code = forward_attributes(rep);
			effects_code = forward_special_effects(rep);	
		}
		break;
	case CHOICE_MINION_CARD:
		{
			cost_code = CreateSingleValTensor(term_info[0]);
			attack_code = CreateSingleValTensor(term_info[1]);
			hp_code = CreateSingleValTensor(term_info[2]);
			attack_times_code = forward_attack_times(rep);
			minion_type_code = forward_minion_type(rep);
			attributes_code = forward_attributes(rep);
			effects_code = forward_special_effects(rep);	
		}
		break;
	case CHOICE_SPELL_CARD:
		{
			cost_code = CreateSingleValTensor(term_info[0]);
			attack_code = CreateZerosTensor(1);
			hp_code = CreateZerosTensor(1);
			attack_times_code = CreateZerosTensor(Attack_Times_Size);
			minion_type_code = CreateZerosTensor(Minion_Type_Size);
			attributes_code = forward_attributes(rep);
			effects_code = forward_special_effects(rep);	
		}
		break;
	}
	torch::Tensor before_dropout = torch::relu(card_root_layer->forward(torch::cat({choice_code, cost_code, attack_code, hp_code, attack_times_code, minion_type_code, attributes_code, effects_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_ZERO_ATTACK 0
#define CHOICE_SINGLE_ATTACK 1
#define CHOICE_MULTIPLE_ATTACK 2
torch::Tensor CardNet::forward_attack_times(NodeRep*& rep) // no network parameters involved
{
	// don't need the choice code as we use will use the actual attack times as code
	const double* term_info = rep->term_info.data();
	int choice = (rep++)->choice;
	double attack_times_val;
	switch(choice)
	{
	case CHOICE_ZERO_ATTACK:
		attack_times_val = NormalizeCode(0, 0, 5);	
		break;
	case CHOICE_SINGLE_ATTACK:
		attack_times_val = NormalizeCode(1, 0, 5);
		break;
	case CHOICE_MULTIPLE_ATTACK:
		attack_times_val = term_info[0];
		break;
	}
	return CreateSingleValTensor(attack_times_val);
}

torch::Tensor CardNet::forward_minion_type(NodeRep*& rep) // no network parameters involved
{
	return CreateOnehotTensor((rep++)->choice, 3);
}

torch::Tensor CardNet::forward_attributes(NodeRep*& rep)  // no network parameters involved
{
	torch::Tensor charge_code = forward_any_attr(rep);
	torch::Tensor taunt_code = forward_any_attr(rep);
	torch::Tensor stealth_code = forward_any_attr(rep);	
	torch::Tensor untargetable_code = forward_any_attr(rep);	
	torch::Tensor shield_code = forward_any_attr(rep);	
	torch::Tensor poisonous_code = forward_any_attr(rep);	
	torch::Tensor lifesteal_code = forward_any_attr(rep);
	return torch::cat({charge_code, taunt_code, stealth_code, untargetable_code, shield_code, poisonous_code, lifesteal_code});	
}

torch::Tensor CardNet::forward_damage_attributes(NodeRep*& rep)  // no network parameters involved
{
	torch::Tensor poisonous_code = forward_any_attr(rep);
	torch::Tensor lifesteal_code = forward_any_attr(rep);
	return torch::cat({poisonous_code, lifesteal_code});	
}

torch::Tensor CardNet::forward_any_attr(NodeRep*& rep) // no network parameters involved
{
	return CreateSingleValTensor((rep++)->choice); // as the choice is binary we only need one bit for this
}

torch::Tensor CardNet::forward_special_effects(NodeRep*& rep)
{
	torch::Tensor targeted_play_eff_code = forward_targeted_play_eff(rep);
	torch::Tensor other_effs_code = forward_other_effs(rep);
	torch::Tensor before_dropout = torch::relu(special_effects_layer->forward(torch::cat({targeted_play_eff_code, other_effs_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_NO_TARGETED_PLAY_EFF 0
#define CHOICE_TARGETED_BATTLECRY_EFF 1
#define CHOICE_TARGETED_CAST_EFF 2
torch::Tensor CardNet::forward_targeted_play_eff(NodeRep*& rep) // no network paramters involved
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 3);
	torch::Tensor effect_code;
	switch(choice)
	{
	case CHOICE_NO_TARGETED_PLAY_EFF:
		effect_code = CreateZerosTensor(Single_Effect_Size);
		break;
	case CHOICE_TARGETED_BATTLECRY_EFF:
	case CHOICE_TARGETED_CAST_EFF:
		effect_code = forward_targeted_eff(rep);
		break;
	}
	return torch::cat({choice_code, effect_code});
}

#define CHOICE_NO_OTHER_EFFS 0
#define CHOICE_CONS_OTHER_EFFS 1
torch::Tensor CardNet::forward_other_effs(NodeRep*& rep) 
{
	// this set of expansion is very special, it is like a sequence model
	// the CHOICE_NO_OTHER_EFFS is like the initial state and the CHOICE_CONS_OTHER_EFFS is like propagating the hidden states through the sequence, which is the part that uses the network parameters
	int choice = (rep++)->choice;
	switch(choice)
	{
	default: // fall through
	case CHOICE_NO_OTHER_EFFS:
		{
			return CreateZerosTensor(Effect_Seq_Size);
		} // don't need break as it returns
	case CHOICE_CONS_OTHER_EFFS:
		{
			torch::Tensor head_eff_code = forward_other_eff(rep);
			torch::Tensor tail_effs_code = forward_other_effs(rep);
			torch::Tensor before_dropout = torch::relu(cons_other_effs_layer->forward(torch::cat({head_eff_code, tail_effs_code})));
			return torch::dropout(before_dropout, Dropout_Rate, is_training());
		} // don't need break ast it returns
	}
}

#define CHOICE_UNTARGETED_BATTLECRY_EFF 0
#define CHOICE_UNTARGETED_CAST_EFF 1
#define CHOICE_DEATHRATTLE_EFF 2
#define CHOICE_ONDISCARD_EFF 3
#define CHOICE_TURN_START_EFF 4
#define CHOICE_TURN_END_EFF 5
torch::Tensor CardNet::forward_other_eff(NodeRep*& rep) // no network parameters involved
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 6);
	torch::Tensor effect_code = forward_untargeted_eff(rep); // all rules share this part as the next node
	torch::Tensor alle_code;
	switch(choice)
	{
	case CHOICE_UNTARGETED_BATTLECRY_EFF:
	case CHOICE_UNTARGETED_CAST_EFF:
	case CHOICE_DEATHRATTLE_EFF:
	case CHOICE_ONDISCARD_EFF:
		alle_code = CreateZerosTensor(Alle_Cond_Size);
		break;
	case CHOICE_TURN_START_EFF:
	case CHOICE_TURN_END_EFF:
		alle_code = forward_allegiance_cond(rep);
		break;
	}
	return torch::cat({choice_code, effect_code, alle_code});
}


#define CHOICE_NO_COND_EFF 0
#define CHOICE_INDE_COND_EFF 1
#define CHOICE_SRC_COND_EFF 2
torch::Tensor CardNet::forward_targeted_eff(NodeRep*& rep)
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 3);
	torch::Tensor effect_code = forward_base_targeted_eff(rep); // all rules share this part as the next node
	torch::Tensor constr_code = forward_target_cond(rep); // all rules share this part and at the next node
	torch::Tensor cond_code;
	switch(choice)
	{
		case CHOICE_NO_COND_EFF:
			cond_code = CreateZerosTensor(Cond_Size);
			break;
		case CHOICE_INDE_COND_EFF:
			cond_code = forward_inde_cond(rep);
			break;
		case CHOICE_SRC_COND_EFF:
			cond_code = forward_target_cond(rep);
			break;
	}
	torch::Tensor before_dropout = torch::relu(targeted_eff_layer->forward(torch::cat({choice_code, effect_code, constr_code, cond_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}
torch::Tensor CardNet::forward_untargeted_eff(NodeRep*& rep)
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 3);
	torch::Tensor effect_code = forward_base_untargeted_eff(rep); // all rules share this part as the next node
	torch::Tensor cond_code;
	switch(choice)
	{
		case CHOICE_NO_COND_EFF:
			cond_code = CreateZerosTensor(Cond_Size);
			break;
		case CHOICE_INDE_COND_EFF:
			cond_code = forward_inde_cond(rep);
			break;
		case CHOICE_SRC_COND_EFF:
			cond_code = forward_target_cond(rep);
			break;
	}
	torch::Tensor before_dropout = torch::relu(untargeted_eff_layer->forward(torch::cat({choice_code, effect_code, cond_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_CHAR_TARGET_COND 0
#define CHOICE_CARD_TARGET_COND 1
torch::Tensor CardNet::forward_target_cond(NodeRep*& rep)
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 2); // we could use just one bit but just doing it in a more generalizable fashion (e.g. in case we have more types there)
	torch::Tensor cond_code;
	switch(choice)
	{
		case CHOICE_CHAR_TARGET_COND:
			cond_code = forward_char_target_cond(rep);
			break;
		case CHOICE_CARD_TARGET_COND:
			cond_code = forward_card_target_cond(rep);
			break;
	}
	torch::Tensor before_dropout = torch::relu(target_cond_layer->forward(torch::cat({choice_code, cond_code}))); // needed for keep equal size as inde_cond
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

torch::Tensor CardNet::forward_char_target_cond(NodeRep*& rep)
{
	torch::Tensor alle_code = forward_allegiance_cond(rep);
	torch::Tensor type_code = forward_char_type_cond(rep);
	torch::Tensor attr_code = forward_attr_cond(rep);
	torch::Tensor stat_code = forward_stat_cond(rep); 
	torch::Tensor before_dropout = torch::relu(char_target_cond_layer->forward(torch::cat({alle_code, type_code, attr_code, stat_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

torch::Tensor CardNet::forward_char_type_cond(NodeRep*& rep) // no network parameters involved
{
	return CreateOnehotTensor((rep++)->choice, 5);
}

torch::Tensor CardNet::forward_card_target_cond(NodeRep*& rep)
{
	torch::Tensor pos_code = forward_card_pos_cond(rep);
	torch::Tensor alle_code = forward_allegiance_cond(rep);
	torch::Tensor type_code = forward_card_type_cond(rep);
	torch::Tensor attr_code = forward_attr_cond(rep);
	torch::Tensor stat_code = forward_stat_cond(rep); 
	torch::Tensor before_dropout = torch::relu(card_target_cond_layer->forward(torch::cat({pos_code, alle_code, type_code, attr_code, stat_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

torch::Tensor CardNet::forward_card_type_cond(NodeRep*& rep) // no network parameters involved
{
	return CreateOnehotTensor((rep++)->choice, 7);
}

torch::Tensor CardNet::forward_card_pos_cond(NodeRep*& rep) // no network parameters involved
{
	return CreateOnehotTensor((rep++)->choice, 3);
}

torch::Tensor CardNet::forward_allegiance_cond(NodeRep*& rep) // no network parameters involved
{
	return CreateOnehotTensor((rep++)->choice, 3);
}

#define CHOICE_NO_ATTR_COND 0
torch::Tensor CardNet::forward_attr_cond(NodeRep*& rep) // no network parameters involved
{
	// save one bit because NO_ATTR_COND really means nothing (no condition)
	int choice = (rep++)->choice;
	switch(choice)
	{
	case CHOICE_NO_ATTR_COND:
		return CreateZerosTensor(7);
	default:
		return CreateOnehotTensor(choice - 1, 7);
	}	
}

#define CHOICE_NO_STAT_COND 0
torch::Tensor CardNet::forward_stat_cond(NodeRep*& rep) // no network parameters involved
{
	// save one bit because NO_STAT_COND really means nothing (no condition)
	int choice = (rep++)->choice;
	torch::Tensor choice_code;
	torch::Tensor variant_code;
	switch(choice)
	{
	case CHOICE_NO_STAT_COND:
		choice_code = CreateZerosTensor(4);
		variant_code = CreateZerosTensor(Stat_Cond_Variant_Size);
		break;
	default:
		choice_code = CreateOnehotTensor(choice - 1, 4);
		variant_code = forward_stat_cond_variant(rep);
		break;
	}
	return torch::cat({choice_code, variant_code});
}

torch::Tensor CardNet::forward_stat_cond_variant(NodeRep*& rep) // no network parameters involved
{
	const double* term_info = rep->term_info.data();
	torch::Tensor choice_code = CreateOnehotTensor((rep++)->choice, 2); // we could use just one bit but just doing it in a more generalizable fashion (e.g. in case we have more types there)
	torch::Tensor val_code = CreateSingleValTensor(term_info[0]);
	return torch::cat({choice_code, val_code});
}

#define CHOICE_FIELD_EXISTENCE_COND 0
#define CHOICE_CARD_EXISTENCE_COND 1
#define CHOICE_LEADER_COND 2
#define CHOICE_MP_COND 3
#define CHOICE_MAX_MP_COND 4
torch::Tensor CardNet::forward_inde_cond(NodeRep*& rep) // involving multiple sets of network parameters
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 5);
	torch::Tensor cond_code;
	switch(choice)
	{
	case CHOICE_FIELD_EXISTENCE_COND:
		cond_code = forward_char_target_cond(rep);
		break;
	case CHOICE_CARD_EXISTENCE_COND:
		cond_code = forward_card_target_cond(rep);
		break;
	case CHOICE_LEADER_COND:
		{
			torch::Tensor alle_code = forward_allegiance_cond(rep);
			torch::Tensor attr_code = forward_attr_cond(rep);
			torch::Tensor stat_code = forward_stat_cond(rep);
			torch::Tensor before_dropout = torch::relu(leader_cond_layer->forward(torch::cat({alle_code, attr_code, stat_code})));
			cond_code = torch::dropout(before_dropout, Dropout_Rate, is_training());
		}
		break;
	case CHOICE_MP_COND:
	case CHOICE_MAX_MP_COND:
		{
			torch::Tensor alle_code = forward_allegiance_cond(rep);
			torch::Tensor variant_code = forward_stat_cond_variant(rep);
			torch::Tensor before_dropout = torch::relu(mp_or_max_cond_layer->forward(torch::cat({alle_code, variant_code})));
			cond_code = torch::dropout(before_dropout, Dropout_Rate, is_training());
		}
		break;
	}
	torch::Tensor before_dropout = torch::relu(inde_cond_layer->forward(torch::cat({choice_code, cond_code}))); // needed for keep equal size as target_cond
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_DAMAGE_EFF 0
#define CHOICE_HEAL_EFF 1
#define CHOICE_RES_ATK_TIMES_EFF 2
#define CHOICE_COST_MOD_EFF 3
#define CHOICE_ATK_HP_MOD_EFF 4
#define CHOICE_ATK_TIMES_MOD_EFF 5
#define CHOICE_DESTROY_EFF 6
#define CHOICE_DISCARD_EFF 7
#define CHOICE_MOVE_EFF 8
#define CHOICE_COPY_EFF 9
#define CHOICE_TRANSFORM_EFF 10
#define CHOICE_CHANGE_TO_BEAST_EFF 11
#define CHOICE_CHANGE_TO_DRAGON_EFF 12
#define CHOICE_CHANGE_TO_DEMON_EFF 13
#define CHOICE_GIVE_GHARGE_EFF 14
#define CHOICE_GIVE_TAUNT_EFF 15
#define CHOICE_GIVE_STEALTH_EFF 16
#define CHOICE_GIVE_UNTARGETABLE_EFF 17
#define CHOICE_GIVE_SHIELD_EFF 18
#define CHOICE_GIVE_POISONOUS_EFF 19
#define CHOICE_GIVE_LIEFSTEAL_EFF 20
#define CHOICE_RM_ATTRIBUTES_EFF 21
#define CHOICE_SET_OVERHEAT_EFF 22
#define CHOICE_DEC_OH_THRESHOLD_EFF 23
#define CHOICE_RESET_STATE_EFF 24
#define CHOICE_GIVE_EFFECTS_EFF 25
torch::Tensor CardNet::forward_base_targeted_eff(NodeRep*& rep) // involving multiple sets of net work parameters
{
	const double* term_info = rep->term_info.data();
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 26);
	torch::Tensor offensive_code;
	torch::Tensor defensive_code;
	torch::Tensor resource_code;
	torch::Tensor utility_code;
	switch(choice)
	{
	case CHOICE_RES_ATK_TIMES_EFF:
	case CHOICE_ATK_TIMES_MOD_EFF:
		offensive_code = CreateSingleValTensor(term_info[0]);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = CreateZerosTensor(Eff_Utility_Size);
		break;
	case CHOICE_HEAL_EFF:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateSingleValTensor(term_info[0]);
		resource_code = CreateZerosTensor(1);
		utility_code = CreateZerosTensor(Eff_Utility_Size);
		break;
	case CHOICE_ATK_HP_MOD_EFF:
		offensive_code = CreateSingleValTensor(term_info[0]);
		defensive_code = CreateSingleValTensor(term_info[1]);
		resource_code = CreateZerosTensor(1);
		utility_code = CreateZerosTensor(Eff_Utility_Size);
		break;
	case CHOICE_COST_MOD_EFF:
	case CHOICE_DEC_OH_THRESHOLD_EFF:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateSingleValTensor(term_info[0]);
		utility_code = CreateZerosTensor(Eff_Utility_Size);
		break;
	case CHOICE_DAMAGE_EFF:
		offensive_code = CreateSingleValTensor(term_info[0]);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = torch::dropout(torch::relu(damage_eff_layer->forward(forward_damage_attributes(rep))), Dropout_Rate, is_training());	
		break;
	case CHOICE_MOVE_EFF:
	case CHOICE_COPY_EFF:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = torch::dropout(torch::relu(move_or_copy_eff_layer->forward(forward_destination(rep))), Dropout_Rate, is_training());
		break;
	case CHOICE_TRANSFORM_EFF:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = torch::dropout(torch::relu(transform_eff_layer->forward(forward_new_card_variant(rep))), Dropout_Rate, is_training());
		break;
	case CHOICE_GIVE_EFFECTS_EFF:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = torch::dropout(torch::relu(give_effects_eff_layer->forward(forward_special_effects(rep))), Dropout_Rate, is_training());
		break;
	default:
		offensive_code = CreateZerosTensor(1);
		defensive_code = CreateZerosTensor(1);
		resource_code = CreateZerosTensor(1);
		utility_code = CreateZerosTensor(Eff_Utility_Size);
		break;
	}
	torch::Tensor before_dropout = torch::relu(base_targeted_eff_layer->forward(torch::cat({choice_code, offensive_code, defensive_code, resource_code, utility_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_AOE_EFF 0
#define CHOICE_RAND_EFF 1
#define CHOICE_LEADER_EFF 2
#define CHOICE_SELF_EFF 3
#define CHOICE_DRAW_CARD_EFF 4
#define CHOICE_MP_EFF 5
#define CHOICE_MAX_MP_EFF 6
#define CHOICE_NEW_EFF 7
#define CHOICE_WIN_GAME_EFF 8
torch::Tensor CardNet::forward_base_untargeted_eff(NodeRep*& rep) // involving multiple sets of network parameters
{
	const double* term_info = rep->term_info.data();
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 9);
	torch::Tensor effect_code;
	torch::Tensor cond_code;
	torch::Tensor val_code;
	switch(choice)
	{
	case CHOICE_AOE_EFF:
	case CHOICE_RAND_EFF:
		effect_code = forward_base_targeted_eff(rep);
		cond_code = forward_target_cond(rep);
		val_code = CreateZerosTensor(1);
		break;
	case CHOICE_LEADER_EFF:
		effect_code = forward_base_targeted_eff(rep);
		cond_code = torch::dropout(torch::relu(alle_to_cond_layer->forward(forward_allegiance_cond(rep))), Dropout_Rate, is_training());
		val_code = CreateZerosTensor(1);
		break;
	case CHOICE_SELF_EFF:
		effect_code = forward_base_targeted_eff(rep);
		cond_code = CreateZerosTensor(Cond_Size);
		val_code = CreateZerosTensor(1);
		break;
	case CHOICE_DRAW_CARD_EFF:
	case CHOICE_MP_EFF:
	case CHOICE_MAX_MP_EFF:
		effect_code = CreateZerosTensor(Base_Targeted_Eff_Size);
		cond_code = torch::dropout(torch::relu(alle_to_cond_layer->forward(forward_allegiance_cond(rep))), Dropout_Rate, is_training());
		val_code = CreateSingleValTensor(term_info[0]);
		break;
	case CHOICE_NEW_EFF:
		{
			torch::Tensor dest_code = forward_destination(rep);
			torch::Tensor variant_code = forward_new_card_variant(rep);
			effect_code = torch::dropout(torch::relu(new_eff_layer->forward(torch::cat({dest_code, variant_code}))), Dropout_Rate, is_training());
		}
		cond_code = CreateZerosTensor(Cond_Size);
		val_code = CreateSingleValTensor(term_info[0]);
		break;
	case CHOICE_WIN_GAME_EFF:
		effect_code = CreateZerosTensor(Base_Targeted_Eff_Size);
		cond_code = torch::dropout(torch::relu(alle_to_cond_layer->forward(forward_allegiance_cond(rep))), Dropout_Rate, is_training());
		val_code = CreateZerosTensor(1);
		break;
	}
	torch::Tensor before_dropout = torch::relu(base_untargeted_eff_layer->forward(torch::cat({choice_code, effect_code, cond_code, val_code})));
	return torch::dropout(before_dropout, Dropout_Rate, is_training());
}

#define CHOICE_FIELD_DEST 0
#define CHOICE_OWN_FIELD_DEST 1
#define CHOICE_HAND_DEST 2
#define CHOICE_OWN_HAND_DEST 3
#define CHOICE_DECK_DEST 4
#define CHOICE_OWN_DECK_DEST 5
torch::Tensor CardNet::forward_destination(NodeRep*& rep) // no network parameters involved
{
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 6);
	torch::Tensor alle_code;
	switch(choice)
	{
	case CHOICE_FIELD_DEST:
	case CHOICE_HAND_DEST:
	case CHOICE_DECK_DEST:
		alle_code = forward_allegiance_cond(rep);
		break;
	case CHOICE_OWN_FIELD_DEST:
	case CHOICE_OWN_HAND_DEST:
	case CHOICE_OWN_DECK_DEST:
		alle_code = CreateZerosTensor(Alle_Cond_Size);
		break;
	}
	return torch::cat({choice_code, alle_code});
}

#define CHOICE_PLAIN_MINION_CARD 0
#define CHOICE_PLAIN_MINION 1
#define CHOICE_FIXED_CARD 2
#define CHOICE_FIXED_MINION 3
#define CHOICE_RANDOM_CARD 4
#define CHOICE_RANDOM_MINION 5
torch::Tensor CardNet::forward_new_card_variant(NodeRep*& rep) // no network parameters involved
{
	const double* term_info = rep->term_info.data();
	int choice = (rep++)->choice;
	torch::Tensor choice_code = CreateOnehotTensor(choice, 6);
	torch::Tensor card_code;
	torch::Tensor cost_code;
	switch(choice)
	{
	case CHOICE_PLAIN_MINION_CARD:
	case CHOICE_PLAIN_MINION:
	case CHOICE_FIXED_CARD:
	case CHOICE_FIXED_MINION:
		card_code = forward_card_root(rep); 
		cost_code = CreateZerosTensor(1);
		break;
	case CHOICE_RANDOM_CARD:
	case CHOICE_RANDOM_MINION:
		card_code = CreateZerosTensor(Card_Root_Size); 
		cost_code = CreateSingleValTensor(term_info[0]);
		break;
	}
	return torch::cat({choice_code, card_code, cost_code});
}


torch::Tensor SingleCardSampleForward(const CardRep& rep, CardNet& model)
{
	NodeRep* node_rep_ptr = (NodeRep*)(rep.data());
	torch::Tensor root_code = model.forward_card_root(node_rep_ptr); 
	return model.forward_out(root_code); 
}


double TrainCardNet(const vector<CardRep>& inputs, const vector<double>& labels, const vector<double>& weights, CardNet& model, torch::optim::SGD& optimizer, ofstream& log_fs)
{
	int num_samples = inputs.size();
	
	// randomly shuffle for each training epoch 
	int* index_list = new int[num_samples];
	for (int i = 0; i < num_samples; i++)
		index_list[i] = i;
	RandShuffle(index_list, num_samples);

	model.train();
	optimizer.zero_grad();
	torch::Tensor sum_loss = CreateZerosTensor(1);
	double sum_weight = 0.0;
	for (int k = 0; k < num_samples; k++)
		sum_weight += weights[k];
	double weight_factor = num_samples/sum_weight;
	double loss_val = 0.0;
	double sqr_err_sum = 0.0;
	for (int i = 1; i <= num_samples; i++)
	{
		int index = index_list[i-1];
		torch::Tensor output = SingleCardSampleForward(inputs[index], model);
		torch::Tensor label = CreateSingleValTensor(labels[index]);
		auto mse_loss_weighted = weight_factor * weights[index] * torch::mse_loss(output, label);
		sqr_err_sum += mse_loss_weighted.template item<double>();
		auto loss = weight_factor * weights[index] * torch::binary_cross_entropy(output, label);
		sum_loss += loss; // accumulating the loss and do the backward after a batch (as opposed to not using sum_loss but do a loss.backward here) is a little more efficient (does not affect the result)
		loss_val += loss.template item<double>();
		if (i % Card_Train_Batch_Size == 0)
		{
			sum_loss.backward();	
			optimizer.step();
			optimizer.zero_grad();
			sum_loss = CreateZerosTensor(1);
		}
	}
	if (num_samples % Card_Train_Batch_Size != 0)
	{
		sum_loss.backward();
		optimizer.step();
	}
	loss_val /= (double)num_samples;
	cout << "Train Loss: " << loss_val << "; Weighted MSE: " << sqr_err_sum/(double)num_samples << endl;
	log_fs << loss_val << " ";

	delete [] index_list;

	return loss_val;
}

double ValidateCardNet(const vector<CardRep>& inputs, const vector<double>& labels, const vector<double>& weights, CardNet& model, ofstream& log_fs)
{
	int num_samples = inputs.size();	

	torch::NoGradGuard no_grad;
	model.eval();
	double sum_weight = 0.0;
	for (int k = 0; k < num_samples; k++)
		sum_weight += weights[k];
	double weight_factor = num_samples/sum_weight;
	double loss_val = 0.0;
	double sqr_err_sum = 0.0;
 	for (int index = 0; index < num_samples; index++)
	{
		torch::Tensor output = SingleCardSampleForward(inputs[index], model);
		torch::Tensor label = CreateSingleValTensor(labels[index]);
		auto mse_loss_weighted = weight_factor * weights[index] * torch::mse_loss(output, label);
		sqr_err_sum += mse_loss_weighted.template item<double>();
		auto loss = weight_factor * weights[index] * torch::binary_cross_entropy(output, label); 
		loss_val += loss.template item<double>();
	}
	loss_val /= (double)num_samples;
	cout << "Validate Loss: " << loss_val << "; Weighted MSE: " << sqr_err_sum/(double)num_samples << endl;
	log_fs << loss_val << " ";

	return loss_val;
}


void TrainCardStrengthPredictor(const vector<CardRep>& train_reps, const vector<double>& train_strengths, const vector<double>& train_weights, const vector<CardRep>& validate_reps, const vector<double>& validate_strengths, const vector<double>& validate_weights, CardNet& model, torch::Device& device, int seed, ofstream& log_fs, const char* train_file, const char* validate_file) // note: device is not used in this version, it may be removed (versions using datesets will need it)
{
	RandInit(seed);
	seed = GetRandInt(); // the seed should be already used once when declaring (initiating) the model so just in case, get the next random number as the new seed

	srand(seed);
	torch::manual_seed(seed);

	// set up the optimizer
	torch::optim::SGD optimizer(model.parameters(), torch::optim::SGDOptions(0.001).momentum(0.5));

	// train/validate
	/*double last_loss_5 = 1000.0; // recording loss value on multiple of 5 (for checking early stopping)
	double current_loss_5 = 1000.0; 
	double last_loss_7 = 1000.0; // recording loss value on multiple of 7 (for checking early stopping)
	double current_loss_7 = 1000.0; 
	double last_loss_11 = 1000.0; // recording loss value on multiple of 11 (for checking early stopping)
	double current_loss_11 = 1000.0;*/
	int epoch;
	for (epoch = 1; epoch <= Card_Num_Epochs; epoch++)
	{
		cout << endl << "Epoch " << epoch << ":" << endl;
		log_fs << epoch << " ";
		TrainCardNet(train_reps, train_strengths, train_weights, model, optimizer, log_fs);
		double validate_loss = ValidateCardNet(validate_reps, validate_strengths, validate_weights, model, log_fs);
		log_fs << endl;
		/*// early stopping criteria, loss on multiple of 5, 7, 11 all increases
		if (epoch % 5 == 0)
		{
			last_loss_5 = current_loss_5;
			current_loss_5 = validate_loss;
			if (current_loss_5 > last_loss_5 && current_loss_7 > last_loss_7 && current_loss_11 > last_loss_11)
			{
				epoch++; // just be consistent in counting number of epochs
				cout << "Early Stopping Triggered." << endl;
				break;
			}
		}
		if (epoch % 7 == 0)
		{
			last_loss_7 = current_loss_7;
			current_loss_7 = validate_loss;
			if (current_loss_5 > last_loss_5 && current_loss_7 > last_loss_7 && current_loss_11 > last_loss_11)
			{
				epoch++; // just be consistent in counting number of epochs
				cout << "Early Stopping Triggered." << endl;
				break;
			}
		}
		if (epoch % 11 == 0)
		{
			last_loss_11 = current_loss_11;
			current_loss_11 = validate_loss;
			if (current_loss_5 > last_loss_5 && current_loss_7 > last_loss_7 && current_loss_11 > last_loss_11)
			{
				epoch++; // just be consistent in counting number of epochs
				cout << "Early Stopping Triggered." << endl;
				break;
			}
		}*/
	}

	int train_size = train_reps.size();
	int validate_size = validate_reps.size();
	cout << "Summary:" << endl;
	cout << "Number of parameters in the model: " << GetModelSize(&model) << endl;
	cout << "Number of epochs: " << epoch - 1 << endl;
	cout << "Train set size: " << train_reps.size() << endl;
	cout << "Validate set size: " << validate_reps.size() << endl;

	// print the prediction vs label on train sets and validation sets to files
	torch::NoGradGuard no_grad;
	model.eval();
	ofstream train_fs(train_file);
	train_fs << train_size << endl;
	for (int i = 0; i < train_size; i++)
	{
		torch::Tensor card_output = SingleCardSampleForward(train_reps[i], model);
		double prediction = card_output.template item<double>();
		double label = train_strengths[i];
		double weight = train_weights[i];
		train_fs << prediction << " " << label << " " << weight << endl;
	}
	train_fs.close();
	train_fs.clear();
	ofstream validate_fs(validate_file);
	validate_fs << validate_size << endl;
	for (int i = 0; i < validate_size; i++)
	{
		torch::Tensor card_output = SingleCardSampleForward(validate_reps[i], model);
		double prediction = card_output.template item<double>();
		double label = validate_strengths[i];
		double weight = validate_weights[i];
		validate_fs << prediction << " " << label << " " << weight << endl;
	}
	validate_fs.close();
	validate_fs.clear();
	
}

double PredictCardStrength(Card* card, CardNet& model)
{
	CardRep card_rep;
	card->FillRep(card_rep);

	torch::NoGradGuard no_grad;
	model.eval();
	torch::Tensor card_output = SingleCardSampleForward(card_rep, model);
	
	return card_output.template item<double>();
}

