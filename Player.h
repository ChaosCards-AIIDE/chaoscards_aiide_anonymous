// note that this is a file containing rep for variety of purposes, approximately indicated by the sections with the comments
// it is not easy to separate into different files due to artifacts from GIGL (not separating header and implementation), which requires all interface to Cards (accessing class member variable or methods, exceptions includes only using the class type) must be defined in one file (here it is Player.cpp)
#pragma once

#include <vector>
#include <queue>
#include <string>
#include <map>
#include <fstream>
#include <torch/torch.h>

#define SUPPRESS_ALL_MSG

using namespace std;


/* Card/Player section */


// type of positions for a card
#define CARD_POS_AT_LEADER 1
#define CARD_POS_AT_FIELD 2
#define CARD_POS_AT_HAND 3
#define CARD_POS_AT_DECK 4
#define CARD_POS_UNKNOWN 5

#define INIT_HAND_SIZE 3
#define MAX_FIELD_SIZE 7
#define MAX_MP 10
#define MAX_HAND_SIZE 10
#define MAX_NUM_TURNS 30 // the design is to make it same as the HP on default leader so that the game can normally end with a rate of losing 1 HP per pair of turns

#define LEADER_CARD 0
#define MINION_CARD 1
#define SPELL_CARD 2

#define NONE_MINION 0
#define BEAST_MINION 1
#define DRAGON_MINION 2
#define DEMON_MINION 3

#define COPY_EXACT 0
#define COPY_ALLY 1
#define COPY_OPPO 2

class Card;
class ActionSetEntity;
class DeferredEvent;

typedef map<void*, void*> PtrRedirMap;
typedef map<void*, void*>::iterator PtrRedirMapIter;

class Player
{
public:
	Player(queue<DeferredEvent*>& _event_queue);
	Player(const string& _name, int _hp, const vector<Card*>& _deck, bool _is_guest, queue<DeferredEvent*>& _event_queue);
	Player(const string& _name, int _hp, const vector<Card*>& _deck, bool _is_guest, queue<DeferredEvent*>& _event_queue, unsigned _ai_level);
	~Player();
	Player* CreateKnowledgeCopy(unsigned mode, queue<DeferredEvent*>& event_queue, PtrRedirMap& redir_map) const; // creating a copy for the purpose of AI exploring; different modes: COPY_EXACT - copy exactly; COPY_ALLY - copy for the allied player (field and hand are preserved, deck is randomly generated); COPY_OPPO - copy for the allied player (only field is preserved, others are randomly generated)
	void RegisterCardContributions(vector<int>& counters); // link each card in the deck to a countribution counter used for evaluating card strength
	void SetAllCardAfflications();
	void SetCardAfflication(Card* card); // used after opponent of the owner is set
	void InitialCardDraw(bool is_second_player); // this should be different from calling DrawCard() a few times, as effects (including fatigue, if any) should not be triggered here
	bool CleanUp(); // process deferred events, clear corpse, check game end etc., return whether game should end
	bool ProcessDeferredEvents(); // return whether game should end; only deal with current event queue
	void ClearCorpse(); // clean spots/cards/minions that should be removed but temporarily retained
	bool CheckGameEnd();
	void FlagDestroy(Card* card, bool start_of_batch);
	void FlagCastSpell(Card* card, bool start_of_batch);
	void FlagFieldDiscard(Card* card, bool start_of_batch);
	void FlagHandDiscard(Card* card, bool start_of_batch);
	void FlagDeckDiscard(Card* card, bool start_of_batch);
	void FlagFieldSummon(Card* card, bool start_of_batch); // if field full, issue a discard event
	void FlagHandPut(Card* card, bool start_of_batch); // if hand full, issue a discard event
	void FlagDeckShuffle(Card* card, bool start_of_batch);
	void FlagCardTransform(Card* card, bool start_of_batch, Card* replacement); // defer the deletion of transformed card
	void FlagCardReset(Card* card, bool start_of_batch); // defer the deletion of extra effects on cards when resetting states
	void SetLose(); // this is mostly used for special effects that grants lost/victory irrelevant to leader health
	bool CheckLose() const;	
	void StartTurn();
	void EndTurn();
	bool CheckPlayValid(int x, int y, int& z); // card x, poistion y, target z (if there is no valid target for a battlecry z will be modified to -1)
	void Play(int x, int y, int z); // card x, poistion y, target z, assume already checked valid
	bool CheckAttackValid(int x, int z); // card x, target z
	void Attack(int x, int z); // card x, target z, assume already checked valid
	void DrawCard(bool start_of_batch);
	void RecoverAttackTimes(); // restore all attack times for friendly characters and switch off their is_first_turn_at_field flag
	bool CheckMP(int cost) const; // return if remaining mp is enough
	void UseMP(int cost);
	void ModifyMp(int amount);
	void ModifyMaxMp(int amount);
	bool IsValidTarget(int z) const; // note that this is intended for targeted (player specified target) effects
	bool IsValidCharTarget(int z) const; // note that this is intended for targeted (player specified target) effects
	bool IsValidMinionTarget(int z) const; // note that this is intended for targeted (player specified target) effects
	bool IsValidCardTarget(int z) const; // note that this is intended for targeted (player specified target) effects
	bool IsTargetAlly(int z) const; // note that this is intended for targeted (player specified target) effects
	bool IsTargetOpponent(int z) const;	// note that this is intended for targeted (player specified target) effects
	Card* GetTargetCard(int z) const;
	Card* ExtractTargetCard(int z); // the target is removed (replaced with nullptr temporarily maintain indexing) from where it is and returned, leaders cannot be removed and is not expected to be a valid input index (will return nullptr if index is for leader or not valid), if the target is dying, also do not remove it here (returns nullptr)
	void SummonToField(Card* card); // does not trigger battlecry, this function itself does not check for field full (if it were full it will be still added but there should be a discard event in the queue right after)
	void PutToHand(Card* card); // if full, this function itself does not check for field full (if it were full it will be still added but there should be a discard event in the queue right after)
	void ShuffleToDeck(Card* card); // the position is randomized
	double GetHeuristicEval() const; // the heuristic about how good the situation is for the player, scaled and clamped within -1 ~ 1 (normally clamped to -0.9 ~ 0.9 unless (almost) lose or win), assumes at end of turn state
	vector<ActionSetEntity*> GetOptionSet();
	void TakeSearchAIInputs();
	void TakeSearchAIInput();
	void TakeRandomAIInputs();
	void TakeRandomAIInput();	
	void TakeInputs();
	void TakeSingleInput();
	void DisplayHelp() const;
	void Query(int x) const;
	string BriefInfo() const;
	string DetailInfo() const;
	void PrintBoard() const;
	int GetActualFieldSize() const; // the actual size, excluding those queued for deletion
	int GetActualHandSize() const; // the actual size, excluding those queued for deletion
	int GetActualDeckSize() const; // the actual size, excluding those queued for deletion
	Card* leader; // essentially a played hero card
	vector<Card*> field; // ordered from left to right
	vector<Card*> hand; // ordered from left to right
	vector<Card*> deck; // ordered from bottom to top
	string name;
	bool is_guest; // whether it is an active controlling player from this terminal (not displaying error message etc.)
	bool is_exploration; // whether the steps it takes is exploring the 
	Player* opponent;
	bool is_lost;
	bool is_turn_active;
	int turn_num;
	int max_mp;
	int mp_loss;
	int fatigue;
	int field_size_adjust; // the discrepancy between the actual size and the size of the vector, due to the existence of deferred events
	int hand_size_adjust; // the discrepancy between the actual size and the size of the vector, due to the existence of deferred events
	int deck_size_adjust; // the discrepancy between the actual size and the size of the vector, due to the existence of deferred events
	queue<DeferredEvent*>& event_queue; // reference to the queue for deferred event (shared between two players)
	int ai_level; // 0 means random ai, 1 ~ 9 means search based ai (the numberical value indicate a scaling factor for the number of search trials)
	void (Player::*input_func)();
};


/* Generator/Descriptor Section */


// Some codings of constraints/conditions on target types
#define TARGET_TYPE_NOTHING 0u
#define TARGET_TYPE_ANY 0xFFFFFFFFu
// target types with different fields
#define TARGET_POS_FIELD 0x1u					// 0b1
#define TARGET_POS_HAND	0x2u					// 0b10
#define TARGET_POS_DECK	0x4u					// 0b100
	#define TARGET_POS_HAND_OR_DECK	0x6u					// 0b110
	#define TARGET_ANY_POS_TYPE 0x7u						// 0b111
	#define TARGET_NOT_HAND	0x5u							// 0b101
	#define TARGET_NOT_DECK 0x3u							// 0b011
#define TARGET_IS_LEADER 0x8u					// 0b1000
#define TARGET_IS_MINION 0x10u					// 0b10000
	#define TARGET_ANY_CHAR 0x18u							// 0b11000
#define TARGET_IS_SPELL	0x20u					// 0b100000
	#define TARGET_ANY_CARD_TYPE 0x38u						// 0b111000
	#define TARGET_NOT_LEADER 0x30u							// 0b110000
	#define TARGET_NOT_MINION 0x28u							// 0b101000
#define TARGET_IS_ALLY 0x40u					// 0b1000000
#define TARGET_IS_OPPO 0x80u					// 0b10000000
	#define TARGET_ANY_ALLE_TYPE 0xC0u						// 0b11000000
	#define TARGET_ANY_CARD_ALLE_TYPE (TARGET_ANY_CARD_TYPE|TARGET_ANY_ALLE_TYPE)
#define TARGET_IS_BEAST 0x100u					// 0b100000000
#define TARGET_IS_DRAGON 0x200u					// 0b1000000000
#define TARGET_IS_DEMON 0x400u					// 0b10000000000
	#define TARGET_ANY_MINION_TYPE 0x700u					// 0b11100000000
	#define TARGET_NOT_BEAST 0x600u							// 0b11000000000
	#define TARGET_NOT_DRAGON 0x500u						// 0b10100000000
	#define TARGET_NOT_DEMON 0x300u							// 0b01100000000
	#define TARGET_ANY_ALLE_MINION_TYPE (TARGET_ANY_ALLE_TYPE|TARGET_ANY_MINION_TYPE)
	#define TARGET_ANY_CHAR_MINION_TYPE (TARGET_ANY_CHAR|TARGET_ANY_MINION_TYPE)
	#define TARGET_ANY_CARD_MINION_TYPE (TARGET_ANY_CARD_TYPE|TARGET_ANY_MINION_TYPE)
	#define TARGET_ANY_CARD_ALLE_MINION_TYPE (TARGET_ANY_CARD_TYPE|TARGET_ANY_ALLE_TYPE|TARGET_ANY_MINION_TYPE)
#define TARGET_IS_CHARGE 0x800u					// 0b100000000000
#define TARGET_IS_TAUNT 0x1000u					// 0b1000000000000
#define TARGET_IS_STEALTH 0x2000u 				// 0b10000000000000
#define TARGET_IS_UNTARGETABLE 0x4000u 			// 0b100000000000000
#define TARGET_IS_SHIELDED 0x8000u 				// 0b1000000000000000
#define TARGET_IS_POISONOUS 0x10000u 			// 0b10000000000000000
#define TARGET_IS_LIFESTEAL 0x20000u 			// 0b100000000000000000
	#define TARGET_ANY_ATTR_TYPE 0x3F800u 					// 0b111111100000000000
	#define	TARGET_NOT_CHARGE 0x3F000u 						// 0b111111000000000000
	#define	TARGET_NOT_TAUNT 0x3E800u 						// 0b111110100000000000
	#define TARGET_NOT_STEALTH 0x3D800u						// 0b111101100000000000
	#define TARGET_NOT_UNTARGETABLE 0x3B800u 				// 0b111011100000000000
	#define TARGET_NOT_SHIELDED 0x37800u 					// 0b110111100000000000
	#define TARGET_NOT_POISONOUS 0x2F800u 					// 0b101111100000000000
	#define TARGET_NOT_LIFESTEAL 0x1F800u 					// 0b011111100000000000
	#define TARGET_SPELL_ATTR 0x34000u						// 0b110100000000000000
	#define TARGETABLE_CHAR_ATTR 0x39800u					// 0b111001100000000000 (targeting one's own stealth minion is allowed but we do not include such dedicated targetting condition)
	#define TARGET_ANY_MINION_ATTR_TYPE (TARGET_ANY_MINION_TYPE|TARGET_ANY_ATTR_TYPE)
	#define TARGET_ANY_ALLE_ATTR_TYPE (TARGET_ANY_ALLE_TYPE|TARGET_ANY_ATTR_TYPE)
	#define TARGET_ANY_CARD_MINION_ATTR_TYPE (TARGET_ANY_CARD_TYPE|TARGET_ANY_MINION_TYPE|TARGET_ANY_ATTR_TYPE)
	#define TARGET_ANY_ALLE_MINION_ATTR_TYPE (TARGET_ANY_ALLE_TYPE|TARGET_ANY_MINION_TYPE|TARGET_ANY_ATTR_TYPE)
	#define TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE (TARGET_ANY_CARD_TYPE|TARGET_ANY_ALLE_TYPE|TARGET_ANY_MINION_TYPE|TARGET_ANY_ATTR_TYPE)
// filters (the aboves are usually combined using bitwise ors (as components), but these are combined using bitwise ands (as full flags))
#define FIELD_COND_FILTER (TARGET_POS_FIELD|TARGET_ANY_CHAR|TARGET_ANY_ALLE_MINION_ATTR_TYPE)
#define HAND_COND_FILTER (TARGET_POS_HAND|TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE)
#define DECK_COND_FILTER (TARGET_POS_DECK|TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE)
#define HAND_OR_DECK_COND_FILTER (TARGET_POS_HAND_OR_DECK|TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE)
#define NOT_HAND_COND_FILTER (TARGET_NOT_HAND|TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE)
#define NOT_DECK_COND_FILTER (TARGET_NOT_DECK|TARGET_ANY_CARD_ALLE_MINION_ATTR_TYPE)
#define LEADER_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_LEADER|TARGET_ANY_ALLE_TYPE|TARGET_NOT_STEALTH)
#define MINION_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_ANY_ALLE_MINION_ATTR_TYPE)
#define CHAR_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CHAR|TARGET_ANY_ALLE_MINION_ATTR_TYPE)
#define SPELL_COND_FILTER (TARGET_POS_HAND_OR_DECK|TARGET_IS_SPELL|TARGET_ANY_ALLE_TYPE|TARGET_SPELL_ATTR)
#define NOT_LEADER_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_NOT_LEADER|TARGET_ANY_ALLE_MINION_ATTR_TYPE)
#define ALLY_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_ALLY|TARGET_ANY_CARD_MINION_ATTR_TYPE)
#define OPPO_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_OPPO|TARGET_ANY_CARD_MINION_ATTR_TYPE)
#define BEAST_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_IS_BEAST|TARGET_ANY_ALLE_ATTR_TYPE)
#define DRAGON_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_IS_DRAGON|TARGET_ANY_ALLE_ATTR_TYPE)
#define DEMON_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_IS_DEMON|TARGET_ANY_ALLE_ATTR_TYPE)
#define NOT_BEAST_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_NOT_BEAST|TARGET_ANY_ALLE_ATTR_TYPE)
#define NOT_DRAGON_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_NOT_DRAGON|TARGET_ANY_ALLE_ATTR_TYPE)
#define NOT_DEMON_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_NOT_DEMON|TARGET_ANY_ALLE_ATTR_TYPE)
#define NOT_CHARGE_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CHAR|TARGET_NOT_CHARGE|TARGET_ANY_ALLE_MINION_TYPE) // this means charge is applicable but not present, similar for the below series about attribute keywords
#define NOT_TAUNT_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CHAR|TARGET_NOT_TAUNT|TARGET_ANY_ALLE_MINION_TYPE)
#define NOT_STEALTH_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_IS_MINION|TARGET_NOT_STEALTH|TARGET_ANY_ALLE_MINION_TYPE)
#define NOT_UNTARGETABLE_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CARD_TYPE|TARGET_NOT_UNTARGETABLE|TARGET_ANY_ALLE_MINION_TYPE)
#define NOT_SHIELDED_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CHAR|TARGET_NOT_SHIELDED|TARGET_ANY_ALLE_MINION_TYPE)
#define NOT_POISONOUS_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CARD_TYPE|TARGET_NOT_POISONOUS|TARGET_ANY_ALLE_MINION_TYPE)
#define NOT_LIFESTEAL_COND_FILTER (TARGET_ANY_POS_TYPE|TARGET_ANY_CARD_TYPE|TARGET_NOT_LIFESTEAL|TARGET_ANY_ALLE_MINION_TYPE)
#define PLAY_CHAR_TARGET_FILTER (TARGET_POS_FIELD|TARGET_ANY_CHAR|TARGET_ANY_ALLE_MINION_TYPE|TARGETABLE_CHAR_ATTR)
#define PLAY_CARD_TARGET_FILTER (TARGET_POS_HAND|TARGET_ANY_CARD_TYPE|TARGET_IS_ALLY|TARGET_ANY_MINION_TYPE|TARGET_NOT_UNTARGETABLE)
#define PLAY_CHAR_SRC_FILTER (TARGET_POS_FIELD|TARGET_ANY_CHAR|TARGET_IS_ALLY|TARGET_ANY_MINION_ATTR_TYPE)
#define PLAY_SPELL_SRC_FILTER (TARGET_POS_HAND|TARGET_IS_SPELL|TARGET_IS_ALLY|TARGET_SPELL_ATTR)
#define DESTROY_SRC_FILTER FIELD_COND_FILTER

// target modes
#define TARGET_MODE_DEFAULT 0u
#define TARGET_MODE_EXIST 1u
#define TARGET_MODE_PLAY 2u
#define TARGET_MODE_SOURCE 3u
#define TARGET_MODE_LEADER 4u
#define TARGET_MODE_SELF 5u
#define TARGET_MODE_NEW 7u
#define TARGET_MODE_MOVE_DEST 7u
#define TARGET_MODE_COPY_DEST 8u
#define TARGET_MODE_NEW_DEST 9u
#define TARGET_MODE_WIN_GAME 10u

// effect timing
#define EFFECT_TIMING_DEFAULT 0u
#define EFFECT_TIMING_PLAY 1u
#define EFFECT_TIMING_DESTROY 2u
#define EFFECT_TIMING_DISCARD 3u
#define EFFECT_TIMING_TURN 4u // includes turn start and turn end


void IntersectRange(int& min_result, int& max_result, int min1, int max1, int min2, int max2);
void IntersectRangeInPlace(int& min_val, int& max_val, int other_min_val, int other_max_val);
void UnionRangeInPlace(int& min_val, int& max_val, int other_min_val, int other_max_val);

class CondConfig
{
public:
	CondConfig(unsigned _flag, int _min_mp, int _max_mp, int _min_max_mp, int _max_max_mp,
		int _min_cost, int _max_cost, int _min_atk, int _max_atk, int _min_hp, int _max_hp, int _min_n_atks, int _max_n_atks); // this is the general version
	CondConfig(unsigned _flag,
		int _min_cost, int _max_cost, int _min_atk, int _max_atk, int _min_hp, int _max_hp, int _min_n_atks, int _max_n_atks); // this is the version without card-independent settings
	CondConfig(unsigned _flag); // only with flag specified, all others are default
	CondConfig(); // default
	CondConfig operator &= (const CondConfig& config);
	CondConfig operator &= (unsigned flag);
	CondConfig operator |= (const CondConfig& config);
	CondConfig operator |= (unsigned flag);
	unsigned operator & (unsigned mask) const;
	unsigned operator | (unsigned mask) const;
	unsigned flag;
	int min_mp, max_mp; // only applicable for card-independent condition
	int min_max_mp, max_max_mp; // only applicable for card-independent condition
	int min_cost, max_cost;
	int min_atk, max_atk;
	int min_hp, max_hp;
	int min_n_atks, max_n_atks;
};

CondConfig GetInitConfigFromCard(const Card* card); // this does not consider the attributes and assume no attributes
CondConfig ExtractEffectIndependentConfig(const CondConfig& config);
CondConfig GetDefaultInitConfig(); // this version is for the initial state of the card, particularly, attribute fields of the flag are zero bits
CondConfig GetDefaultConfig(); // just a constructor like function, due to artifact from GIGL
CondConfig GetFlagConfig(unsigned flag);
CondConfig GetMpConfig(int min_mp, int max_mp);
CondConfig GetMaxMpConfig(int min_max_mp, int max_max_mp);
CondConfig GetCostConfig(unsigned flag, int min_cost, int max_cost);
CondConfig GetAtkConfig(unsigned flag, int min_atk, int max_atk);
CondConfig GetHpConfig(unsigned flag, int min_hp, int max_hp);
CondConfig GetAtkTimesConfig(unsigned flag, int min_n_atks, int max_n_atks);

extern bool display_overheat_counts; // whether or not to display overheat counter in detailed discripition.

string MinionTypeDescription(int type);
string AttributeDescriptionInline(bool is_charge, bool is_taunt, bool is_stealth, bool is_untargetable, bool is_shielded, bool is_poisonous, bool is_lifesteal); // comma separated list, starting with a " with " if there's any attribute
string AttributeDescriptionBrief(bool is_charge, bool is_taunt, bool is_stealth,bool is_untargetable,bool is_shielded,bool is_poisonous, bool is_lifesteal);
string AttributeDescriptionDetail(bool is_charge, bool is_taunt, bool is_stealth, bool is_untargetable, bool is_shielded, bool is_poisonous, bool is_lifesteal, int indent_size);


/* Simulator Section */

int GetGiglRandInt(); // artifact from file including issues
int GetGiglRandInt(int n); // artifact from file including issues
double GetGiglRandFloat(); // 0.0 ~ 1.0; artifact from file includeing issues
double GetGiglRandFloat(double max_val); // 0.0 ~ max_val; artifact from file including issues
vector<int> CreateRandomSelection(int n, int k); // select random k numbers from 0 ~ n-1 as a list (ordered randomly); artifact from file including issues
vector<int> CreateRandomSelectionSorted(int n, int k); // same as above but return guarantee sorted in increasing order 
Card* GenerateSingleCard(int seed);
string GetCardBrief(Card* card); // artifact from file including issues
string GetCardDetail(Card* card); // artifact from file including issues
vector<Card*> GenerateRandDeck(int n, int seed);
vector<int> GenerateCardSetSeeds(int n, int seed);
vector<Card*> GenerateRandDeckFromSeedList(const vector<int>& seeds);
void InitMatch(const vector<int>& seed_list, vector<int>& deck_a_indices, vector<int>& deck_b_indices, vector<int>& deck_a_seeds, vector<int>& deck_b_seeds); // shuffle the card indices, return the seed for the match (also modify shuffled indices in place, and pass back the ordered seeds for this match)
void DecidePlayOrder(Player* player1, Player* player2, Player*& first_player, Player*& second_player);
void DeleteCard(Card* card); // artifact from file including issues


class DeferredEvent // certain parts of effects are not applied immediately but rather pushed into a queue and dealt with afterwards, this is because we don't want inserted events to AoE effects, and also sometimes we want to maintain target indexing unchanged until the effects on one card at a certain point is fully executed
{
public:
	DeferredEvent(Card* _card, bool _start_of_batch);
	virtual void Process(Player* curr_player) = 0;

protected:
	Card* card;

public:
	bool is_start_of_batch;
};

class DestroyEvent : public DeferredEvent
{
public:
	DestroyEvent(Card* _card, bool _start_of_batch);
	virtual void Process(Player* curr_player);
};

class CastEvent : public DeferredEvent // currently not actually needed as there isn't anything special to do after a spell is cast
{
public:
	CastEvent(Card* _card, bool _start_of_batch);
	virtual void Process(Player* curr_player);
};

class DiscardEvent : public DeferredEvent
{
public:
	DiscardEvent(Card* _card, bool _start_of_batch);
	virtual void Process(Player* curr_player);
};

class FieldSummonEvent : public DeferredEvent
{
public:
	FieldSummonEvent(Card* _card, bool _start_of_batch, Player* _owner);
	virtual void Process(Player* curr_player);

private:
	Player* owner;
};

class HandPutEvent : public DeferredEvent
{
public:
	HandPutEvent(Card* _card, bool _start_of_batch, Player* _owner);
	virtual void Process(Player* curr_player);

private:
	Player* owner;
};

class DeckShuffleEvent : public DeferredEvent
{
public:
	DeckShuffleEvent(Card* _card, bool _start_of_batch, Player* _owner);
	virtual void Process(Player* curr_player);

private:
	Player* owner;
};

class CardTransformEvent : public DeferredEvent
{
public:
	CardTransformEvent(Card* _card, bool _start_of_batch, Card* _replacement);
	virtual void Process(Player* curr_player);

private:
	Card* replacement;
};

class CardResetEvent : public DeferredEvent // currently not actually needed as there isn't anything special to do after a card is reset to its original state
{
public:
	CardResetEvent(Card* _card, bool _start_of_batch);
	virtual void Process(Player* curr_player);
};


/* AI Section */


class ActionEntity
{
public:
	ActionEntity();
	virtual bool CheckValid(Player* player) const = 0;
	virtual void PerformAction(Player* player) const = 0;
};

class PlayAction : public ActionEntity
{
public:
	PlayAction(int _src, int _pos, int _des);
	virtual bool CheckValid(Player* player) const;
	virtual void PerformAction(Player* player) const;

private:
	int src;
	int pos;
	int des;	
};

class AttackAction : public ActionEntity
{
public:
	AttackAction(int _src, int _des);
	virtual bool CheckValid(Player* player) const;
	virtual void PerformAction(Player* player) const;

private:
	int src;
	int des;
};

class EndTurnAction : public ActionEntity
{
public:
	EndTurnAction();
	virtual bool CheckValid(Player* player) const;
	virtual void PerformAction(Player* player) const;
};

class ActionSetEntity // for the set of valid actions for to play/attack with a specific card, or end turn
{
public:
	ActionSetEntity();
	~ActionSetEntity(); // probably don't need virtual as there's nothing to do in the child class destructor
	virtual int CreateValidSet(Player* player) = 0; // return the size of the set of valid actions
	virtual int RecheckValidity(Player* player) = 0; // check if the current actions are still valid (mostly with a different state), remove actions that are no longer valid, returning the number of valid actions remaining
	virtual void PerformRandomAction(Player* player) const = 0;
	vector<ActionEntity*> action_set;
};

class PlayActionSet : public ActionSetEntity
{
public:
	PlayActionSet(int _card_index);
	virtual int CreateValidSet(Player* player);
	virtual int RecheckValidity(Player* player);
	virtual void PerformRandomAction(Player* player) const;

private:
	int card_index;
};

class AttackActionSet : public ActionSetEntity
{
public:
	AttackActionSet(int _card_index);
	virtual int CreateValidSet(Player* player);
	virtual int RecheckValidity(Player* player);
	virtual void PerformRandomAction(Player* player) const;

private:
	int card_index;
};

class EndTurnActionSet : public ActionSetEntity
{
public:
	EndTurnActionSet();
	virtual int CreateValidSet(Player* player);
	virtual int RecheckValidity(Player* player);
	virtual void PerformRandomAction(Player* player) const;
};

class KnowledgeActionNode
{
public:
	KnowledgeActionNode(const ActionEntity* _action); // it does not need a destructor to delete the action as it will be managed by the ActionSetEntity that owns it anyway
	const ActionEntity* GetAction() const;
	double TestAction(Player* player); // do a single test of action (try a single trajectory), return the heuristic evaluation at the end of the simulated turn
	int num_visits;
	double sum_eval;
	double ave_eval;

private:
	const ActionEntity* action;
};

class KnowledgeOptionNode
{
public:
	KnowledgeOptionNode(const ActionSetEntity* _action_set);
	~KnowledgeOptionNode();
	const KnowledgeActionNode* GetOptimalActionNode() const; // optimal action after testing/searching
	double TestAction(Player* player); // do a single test of action (try a single trajectory), return the heuristic evaluation at the end of the simulated turn
	int num_visits;
	double sum_eval;
	double ave_eval;
	
private:
	vector<KnowledgeActionNode*> action_nodes;
};

class KnowledgeState
{
public:
	KnowledgeState(Player* _player, queue<DeferredEvent*>& event_queue, PtrRedirMap& redir_map);
	~KnowledgeState();
	const ActionEntity* GetOptimalAction() const; // optimal action after testing/searching
	double TestAction(Player* player); // do a single test of action (try a single trajectory), return the heuristic evaluation at the end of the simulated turn
	void PerformAction(); // test (with a biased tree search) and execute the action of choice (optimal action)
	int num_visits;

private:
	vector<KnowledgeOptionNode*> option_nodes;
	int num_actions; // total number of actions (not necessarily equal to the number of option nodes, as each option node may correspond to multiple actions)
	int num_tests_scaling; // a scaling factor for number of trials (the number of trials is also related to the number of legal actions)
	Player* orig_player; // the player for taking actual action
	Player* ally_player;
	Player* oppo_player;
};


/* Machine Learning Section */


struct NodeRep
{
	NodeRep(int _choice, const vector<double>& _term_info);
	string GetPrintVersion() const;
	int choice;
	vector<double> term_info;
};
typedef vector<NodeRep> CardRep;

typedef vector<torch::Tensor> CardCode;

NodeRep mkNodeRep(int choice, const vector<double>& term_info);
NodeRep mkNodeRep(int choice);

double NormalizeCode(double val, double min_val, double max_val); // normalize to -1.0 ~ 1.0
void GetCardRepsFromSeeds(const vector<int>& seed_list, vector<CardRep>& card_reps);


torch::Tensor CreateZerosTensor(size_t size);
torch::Tensor CreateSingleValTensor(double val);
torch::Tensor CreateOnehotTensor(int choice, size_t size);

int GetModelSize(const torch::nn::Module* model); // return the number of parameters in the model

struct CardNet : torch::nn::Module
{
	CardNet();
	// forwarding methods
	torch::Tensor forward_out(const torch::Tensor& root_code);
	torch::Tensor forward_card_root(NodeRep*& rep);
	torch::Tensor forward_attack_times(NodeRep*& rep);
	torch::Tensor forward_minion_type(NodeRep*& rep);
	torch::Tensor forward_attributes(NodeRep*& rep);
	torch::Tensor forward_damage_attributes(NodeRep*& rep);
	torch::Tensor forward_any_attr(NodeRep*& rep);
	torch::Tensor forward_special_effects(NodeRep*& rep);
	torch::Tensor forward_targeted_play_eff(NodeRep*& rep);
	torch::Tensor forward_other_effs(NodeRep*& rep);
	torch::Tensor forward_other_eff(NodeRep*& rep);
	torch::Tensor forward_targeted_eff(NodeRep*& rep);
	torch::Tensor forward_untargeted_eff(NodeRep*& rep);
	torch::Tensor forward_target_cond(NodeRep*& rep);
	torch::Tensor forward_char_target_cond(NodeRep*& rep);
	torch::Tensor forward_char_type_cond(NodeRep*& rep);
	torch::Tensor forward_card_target_cond(NodeRep*& rep);
	torch::Tensor forward_card_type_cond(NodeRep*& rep);
	torch::Tensor forward_card_pos_cond(NodeRep*& rep);
	torch::Tensor forward_allegiance_cond(NodeRep*& rep);
	torch::Tensor forward_attr_cond(NodeRep*& rep);
	torch::Tensor forward_stat_cond(NodeRep*& rep);
	torch::Tensor forward_stat_cond_variant(NodeRep*& rep);
	torch::Tensor forward_inde_cond(NodeRep*& rep);
	torch::Tensor forward_base_targeted_eff(NodeRep*& rep);
	torch::Tensor forward_base_untargeted_eff(NodeRep*& rep);
	torch::Tensor forward_destination(NodeRep*& rep);
	torch::Tensor forward_new_card_variant(NodeRep*& rep);
	// layers/parameters
	torch::nn::Linear hidden_to_out;
	torch::nn::Linear hidden_1_to_hidden_2;
	torch::nn::Linear root_to_hidden;
	torch::nn::Linear card_root_layer;
	torch::nn::Linear special_effects_layer;
	torch::nn::Linear cons_other_effs_layer;
	torch::nn::Linear targeted_eff_layer;
	torch::nn::Linear untargeted_eff_layer;
	torch::nn::Linear target_cond_layer;
	torch::nn::Linear char_target_cond_layer;
	torch::nn::Linear card_target_cond_layer;
	torch::nn::Linear inde_cond_layer;
	torch::nn::Linear leader_cond_layer;
	torch::nn::Linear mp_or_max_cond_layer;
	torch::nn::Linear base_targeted_eff_layer;
	torch::nn::Linear damage_eff_layer;
	torch::nn::Linear move_or_copy_eff_layer;
	torch::nn::Linear transform_eff_layer;
	torch::nn::Linear give_effects_eff_layer;
	torch::nn::Linear base_untargeted_eff_layer;
	torch::nn::Linear alle_to_cond_layer;
	torch::nn::Linear new_eff_layer;
};


torch::Tensor SingleCardSampleForward(const CardRep& rep, CardNet& model);

double TrainCardNet(const vector<CardRep>& inputs, const vector<double>& labels, const vector<double>& weights, CardNet& model, torch::optim::SGD& optimizer, ofstream& log_fs); // return loss value
double ValidateCardNet(const vector<CardRep>& inputs, const vector<double>& labels, const vector<double>& weights, CardNet& model, ofstream& log_fs); // return loss value

void TrainCardStrengthPredictor(const vector<CardRep>& train_reps, const vector<double>& train_strengths, const vector<double>& train_weights, const vector<CardRep>& validate_reps, const vector<double>& validate_strengths, const vector<double>& valdiate_weights, CardNet& model, torch::Device& device, int seed, ofstream& log_fs, const char* train_file, const char* validate_file);
double PredictCardStrength(Card* card, CardNet& model);

