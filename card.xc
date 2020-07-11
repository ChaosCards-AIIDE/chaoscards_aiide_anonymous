giglstart;

import "Player.h";
import <iostream>;

#define SUPPRESS_ALL_MSG

#define DEFAULT_OVERHEAT_THRESHOLD 10
#define MAX_OVERHEAT_THRESHOLD 10

#define NOT_LEADR_PARAM 0.9 // a prob. parameter for not allowing played leaders be a valid target (not allowing leader vs not allowing on field)
#define NOT_POS_PARAM 0.9 // a prob. parameter for not allowing moving to the same type of position, i.e. field to field, hand to hand, deck to deck (not allowing same type of position vs not allowing moving to same allegiance)

class Player;
class CondConfig;
class Card;
typedecl PtrRedirMap;
typedecl PtrRedirMapIter;
typedecl CardRep;

giglconfig GetDefaultGenConfig(int seed);
Card* CreatePlainMinion(string parent_name);
Card* CreateRandomMinion(string parent_name, int cost, int min_eff_num, int max_eff_num, int eff_depth);
Card* CreateRandomCard(string parent_name, int cost, int min_eff_num, int max_eff_num, int eff_depth);

gigltype Card{int seed, int max_eff_num, int max_eff_depth}:
{
wrapper:
	initializer
	{
		contribution = nullptr;
		is_dying = false;
		is_resetting = false;
		replacement = nullptr;
		is_first_turn_at_field = false;
		owner = nullptr;
		opponent = nullptr;
		card_pos = CARD_POS_UNKNOWN;
		orig_mana = mana = -1;
		orig_atk = atk = -1;
		orig_hp = max_hp = -1;
		hp_loss = 0;
		orig_n_atks = max_n_atks = -1;
		n_atks_loss = 0;
		orig_minion_type = minion_type = NONE_MINION;
		orig_is_charge = is_charge = false;
		orig_is_taunt = is_taunt = false;
		orig_is_stealth = is_stealth = false;
		orig_is_untargetable = is_untargetable = false;
		orig_is_shielded = is_shielded = false;
		orig_is_poisonous = is_poisonous = false;
		orig_is_lifesteal = is_lifesteal = false;
	}
	generator
	{
		name = "#" + IntToStr(seed);
		CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
		root = generate CardRoot(tmp_config, false); // currently we only control the type and cost through the config so the issue on the range for hp is not a problem 
	}
	destructor
	{
		ClearExtraEffects();
	}
	void RegisterContribution(int* counter)
	{
		contribution = counter;
	}
	void IncContribution()
	{
		if (contribution)
			(*contribution)++;
	}
	void SetAffiliation(Player* _owner)
	{
		owner = _owner;
		opponent = _owner->opponent;
	}
	int GetTargetIndex() // should limit the usage of this function as much as possible
	{
		if (owner->leader == item)
			return 0;
		for (int i = 0; i < owner->field.size(); i++)
			if (owner->field[i] == item)
				return i + 1;
		for (int i = 0; i < owner->hand.size(); i++)
			if (owner->hand[i] == item)
				return i + owner->field.size() + opponent->field.size() + 2;
		for (int i = 0; i < owner->deck.size(); i++)
			if (owner->deck[i] == item)
				return i + owner->field.size() + owner->hand.size() + opponent->field.size() + 2;
		return -1;  // shouldn't happen
	}
	string BriefInfo()
	{
		return name + ", " + root->Brief();
	} 
	string DetailInfo()
	{
		return "Name: " + name + ".\n" + root->DetailIndent(0); 
	}
	bool IsSleeping() // use a getter to get dynamically so that it is easier to deal with giveCharge, removeAttributes, resetState etc.
	{
		return is_first_turn_at_field && !is_charge;
	}
	bool isTargetedAtPlay(int x, int y)
	{
		return root->isTargetedAtPlay(x, y, item);
	} 
	bool CheckPlayValid(int x, int y, int& z) 
	{ 
		return root->CheckPlayValid(x, y, z, item);
	} 
	void Play(int x, int y, int z)
	{
		root->Play(x, y, z, item);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->Play(x, y, z, item);
	} 
	void Destroy()
	{
		root->Destroy(item);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->Destroy(item);
	}
	void Discard()
	{
		root->Discard(item);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->Discard(item);
	}
	bool CheckAttackValid(int x, int z) 
	{ 
		return root->CheckAttackValid(x, z, item); // currently assuming effects does not affect what target is valid to attack (so nor do the extra effects)
	}
	void Attack(int x, int z)
	{
		root->Attack(x, z, item);
		// currently there no on attack effects are implemented yet so extra effects are not yet included here
		/*
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->Attack(x, z, item);
		*/
	}
	void TurnStart(Card* leader)
	{
		root->TurnStart(leader, item);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->TurnStart(leader, item);
	}
	void TurnEnd(Card* leader)
	{
		root->TurnEnd(leader, item);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->TurnEnd(leader, item);
	}
	void SetAllOverheatCounts(int val) // has to use a different name as the node version due to artifacts from GIGL (if the signature is the same then it'll collide with the auto-added duplicates of the node version)
	{
		root->SetOverheatCounts(val);
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->SetOverheatCounts(val);
	}
	void SetAllOverheatThresholds(int val) // has to use a different name as the node version due to artifacts from GIGL (if the signature is the same then it'll collide with the auto-added duplicates of the node version)
	{
		root->SetOverheatThresholds(val); // note the amount here is always negative
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->SetOverheatThresholds(val);
	}
	void ModAllOverheatThresholds(int amount) // has to use a different name as the node version due to artifacts from GIGL (if the signature is the same then it'll collide with the auto-added duplicates of the node version)
	{
		root->ModOverheatThresholds(amount); // note the amount here is always negative
		for (int i = 0; i < effects_extra.size(); i++)
			effects_extra[i]->ModOverheatThresholds(amount);
	}
	void TakeDamage(int amount, Card* src, bool start_of_batch)
	{
		if (is_shielded)
		{
			if (amount > 0)
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!owner->is_exploration)
					cout << "Damage to " << owner->name << "\'s " << name << " absorbed by divine shield." << endl;
				#endif
				is_shielded = false;
			}
			if (src && src->is_poisonous)
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!owner->is_exploration)
					cout << "Poision to " << owner->name << "\'s " << name << " absorbed by divine shield." << endl;
				#endif
				is_shielded = false;
			}
			#ifndef SUPPRESS_ALL_MSG
			if (!owner->is_exploration)
			{
				if (is_shielded)
					cout << "Zero damage to " << owner->name << "\'s " << name << " does not break the divine shield" << endl;
				else
					cout << owner->name << "\'s " << name << "\'s divine shield consumed." << endl;
			}
			#endif
		}
		else
		{
			#ifndef SUPPRESS_ALL_MSG
			if (!owner->is_exploration)
				cout << IntToStr(amount) << " damage dealt to " << owner->name << "\'s " << name << "." << endl;
			#endif
			// reduce health before checking for lifesteal (for cases like dealing damage to your own leader with lifesteal, so that at full/near full health the hp restore will not be wasted because of overflowing)
			// note, leader with lifesteal attacking a minion will always first restore health because the counter attack is always computed later (so leader attacking at full health to a minion may actualy waste hp retore because of overflowing)
			hp_loss += amount;
			if (src && src->is_lifesteal && !src->owner->leader->is_dying)
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!owner->is_exploration)
					cout << src->owner->name << "\'s " << src->name << " lifesteal attribute activated." << endl;
				#endif
				src->owner->leader->RestoreHp(amount);
			}
			if (hp_loss >= max_hp) // do this check after checking lifesteal because for cases like dealing damage to your own leader with lifesteal it shouldn't destroyed if lifesteal gets it back
				owner->FlagDestroy(item, start_of_batch);
			if (src && src->is_poisonous && card_type == MINION_CARD) // poison does not apply to leader
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!owner->is_exploration)
					cout << src->owner->name << "\'s " << src->name << " poisonous attribute activated." << endl;
				#endif
				if (!is_dying) // to prevent double-destroy (there'a another potential destroy above)
					owner->FlagDestroy(item, start_of_batch);
			}
		}
	}
	void RestoreHp(int amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!owner->is_exploration)
			cout << IntToStr(amount) << " health restored to " << owner->name << "\'s " << name << "." << endl;
		#endif
		if (hp_loss < amount)
		{
			#ifndef SUPPRESS_ALL_MSG
			if (!owner->is_exploration)
				cout << "Actually only restored " << IntToStr(hp_loss) << "." << endl;
			#endif
			hp_loss = 0;
		}
		else
		{
			hp_loss -= amount;
		}
	}
	void RestoreAtkTimes(int amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!owner->is_exploration)
			cout << IntToStr(amount) << " attack times restored to " << owner->name << "\'s " << name << "." << endl;
		#endif
		if (n_atks_loss < amount)
		{
			#ifndef SUPPRESS_ALL_MSG
			if (!owner->is_exploration)
				cout << "Actually only restored " << IntToStr(n_atks_loss) << "." << endl;
			#endif
			n_atks_loss = 0;
		}
		else
		{
			n_atks_loss -= amount;
		}
	}
	void ModifyAtkHp(int atkmod, int hpmod) // assume hpmod >= 0
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!owner->is_exploration)
			cout << (atkmod < 0 ? "" : "+") << IntToStr(atkmod) << "/" << (hpmod < 0 ? "" : "+") << IntToStr(hpmod) << " given to " << owner->name << "\'s " << name << "." << endl;
		#endif
		atk += atkmod;
		if (atk < 0)
			atk = 0;
		max_hp += hpmod;
	}
	void ModifyCost(int amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!owner->is_exploration)
			cout << (amount < 0 ? "" : "+") << IntToStr(amount) << " applied to the mana cost of " << owner->name << "\'s " << name << "." << endl;
		#endif
		mana += amount;
		if (mana < 0)
			mana = 0; 
	}
	void ModifyAtkTimes(int amount)
	{
		#ifndef SUPPRESS_ALL_MSG
		if (!owner->is_exploration)
			cout << (amount < 0 ? "" : "+") << IntToStr(amount) << " applied to the atk times of " << owner->name << "\'s " << name << "." << endl;
		#endif
		max_n_atks += amount;
		if (max_n_atks < 0)
			max_n_atks = 0;
	}
	int* contribution; // pointer to the counter for contribution (for evaluation of card strength), if nullptr, then it means the match is not used for evaluation
	string name;
	bool is_dying; // for deferred card removal
	bool is_resetting; // for deferred removal of extra effects
	Card* replacement; // used for tranform effect (deferred mechanism)
	bool is_first_turn_at_field; // whether it is the first turn the charactor come on to the field
	Player* owner;
	Player* opponent;
	int card_pos;
	int mana;
	int orig_mana;
	int atk;
	int orig_atk;
	int max_hp;
	int orig_hp;
	int hp_loss;
	int max_n_atks;
	int orig_n_atks;
	int n_atks_loss;
	int card_type;
	int minion_type;
	int orig_minion_type;
	bool is_charge;
	bool orig_is_charge;
	bool is_taunt;
	bool orig_is_taunt;
	bool is_stealth;
	bool orig_is_stealth;
	bool is_untargetable;
	bool orig_is_untargetable;
	bool is_shielded;
	bool orig_is_shielded;
	bool is_poisonous;
	bool orig_is_poisonous;
	bool is_lifesteal;
	bool orig_is_lifesteal;
	
node:
	void FillRep(CardRep& rep);
	string Brief() { return ""; }
	string Detail() { return ""; }
	string DetailIndent(int indent_size) { return RepeatSpace(indent_size) + Detail(); }
	string DetailAlt1() { return Detail(); } // for different phrasing, similar below
	string DetailAlt2() { return Detail(); }
	string DetailAlt3() { return Detail(); }
	string DetailAlt4() { return Detail(); }
	string DetailAlt5() { return Detail(); }
	string DetailAlt6() { return Detail(); }
	string Suffix() { return ""; } // for two-part description
	string SuffixAlt1() { return Suffix(); }
	string Postfix { return "\n"; } // for nesting (even after Suffix), the default newline is adopted for easy print formatting
	string PostfixIndent(int indent_size) { return Postfix(); }
	bool IsPlural() { return false; }
	bool IsThirdPersonSingle() { return false; }
	Node* CreateNodeHardCopy(Card* card_copy, PtrRedirMap& redir_map) { return nullptr; }
	int GetEffectNum() { return 0; }
	SpecialEffects* GetEffects() { return nullptr; }
	Card* GetRelatedCard(Card* parent_card) { return nullptr; }
	bool isCondTrivial() { return false; }
	unsigned GetInitAttrFlag() { return TARGET_TYPE_NOTHING; } // this is applied with bitwise or's so the default should be all zeros, this shouldn't be needed until we construct the card in parts (because generator would just modify the config in place)
	CondConfig GetPlayTargetConfig() { return GetTargetConfig(); } // for the target of a targeted effect
	CondConfig GetGlobalSelfConfig(const CondConfig& self_config, unsigned effect_timing) { return GetTargetConfig(); } // for getting constraints for effects that gives effects to cards
	CondConfig GetSelfConfig(const CondConfig& self_config) { return GetTargetConfig(); } // for getting constraints for source condition, those are mostly caused by self-targetting effects
	CondConfig GetLeaderConfig() { return GetTargetConfig(); }
	CondConfig GetTargetConfig() { return GetDefaultConfig(); } // this is the most basic version, for general use (untargeted version)
	void AdjustGlobalStatRange(int& min_val, int& max_val) {}
	bool isTargetedAtPlay(int x, int y, Card* parent_card) { return false; } // might related to position as some effects could be made only be able to specify target when played from and/or at specific positions; parent card is needed to accommodate the need of sharing effects accross cards
	bool CheckPlayValid(int x, int y, int& z, Card* parent_card) { return true; } 
	void Play(int x, int y, int z, Card* parent_card) {} // assuming valid
	void Destroy(Card* parent_card) {}
	void Discard(Card* parent_card) {}
	bool CheckAttackValid(int x, int z, Card* parent_card) { return true; }
	void Attack(int x, int z, Card* parent_card) {} // assuming valid	
	void TurnStart(Card* leader, Card* parent_card) {}
	void TurnEnd(Card* leader, Card* parent_card) {}
	bool TargetedAction(int z, Card* parent_card, bool start_of_batch) { return false; } // return whether a deferred event is added to the event queue during the execution of this function (including calling other functions, but not including events added afterwards caused by changes by the function), used for AoE or other effects that must be all be checked for a potential draw
	void SubTargetedAction(Card* target, Card* parent_card, bool start_of_batch) {}
	void UntargetedAction(Card* parent_card) {}
	bool CheckCardValid(Card* card, Card* parent_card) { return true; } // well currently it might not need the parent_card argument but if there were conditions like having attack more than this card etc. then it would be needed
	bool CheckThisValid(Card* parent_card) { return true; }
	bool CheckStatValid(int stat_val) { return true; }
	void Mutate(int min_eff_n, int max_eff_n, int effect_depth) {} // redo effects and attack times (used to do the two-step child card generation to overcome ableC artifacts), may add poisonous and lifesteal attributes but does not change any other attribute
	void SetOverheatCounts(int val)
	{
		overheat_count = val;
	}
	void SetOverheatThresholds(int val)
	{
		overheat_threshold = val;
		if (overheat_threshold < 0)
			overheat_threshold = 0;
		else if (overheat_threshold > MAX_OVERHEAT_THRESHOLD)
			overheat_threshold = MAX_OVERHEAT_THRESHOLD;
	}
	void ModOverheatThresholds(int amount) // note the amount here is always negative
	{
		overheat_threshold += amount;
		if (overheat_threshold < 0)
			overheat_threshold = 0;
		else if (overheat_threshold > MAX_OVERHEAT_THRESHOLD)
			overheat_threshold = MAX_OVERHEAT_THRESHOLD;
	}
	int num_refs; // number of references, for sharing nodes; currently only effective on special effects, stored at SpecialEffects level
	int overheat_count; // the number of times an effect (aggregated for ones from the same source, which are stored in the same address anyway) is triggered during a pair of turns, cleared at the end of your turns; the mechanism is used to prevent overly long action/turns from repeated activation of the same effect, stored at the TargetedEff or UntargetedEff level
	int overheat_threshold; // the max number an effect may be triggered during a pair of turns, default is 10

nonterminal:
	CardRoot(CondConfig& global_config, bool is_plain); // if is_plain is true, then force no effects and single attack
	AttackTimes;
	MinionType;
	Attributes(CondConfig& self_config, int damage);
	DamageAttributes(CondConfig& self_config, unsigned target_mode, int damage);
	ChargeAttr(CondConfig& self_config);
	TauntAttr(CondConfig& self_config);
	StealthAttr(CondConfig& self_config);
	UntargetableAttr(CondConfig& self_config);
	ShieldAttr(CondConfig& self_config);
	PoisonousAttr(CondConfig& self_config, int damage);
	LifestealAttr(CondConfig& self_config, int damage);
	SpecialEffects(CondConfig& self_config, int min_n, int max_n, int effect_depth, bool give_eff); // give_eff denotes whether this is generated inside a giveEffectsEff
	TargetedPlayEff(CondConfig& self_config, int effect_depth, bool give_eff);
	OtherEffs(CondConfig& self_config, int min_n, int max_n, int effect_depth, bool give_eff);
	OtherEff(CondConfig& self_config, int effect_depth, bool give_eff);
	TargetedEff(CondConfig& self_config, unsigned effect_timing, int effect_depth, bool give_eff);
	UntargetedEff(CondConfig& self_config, unsigned effect_timing, int effect_depth, bool give_eff);
	TargetCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing); // init_config applies refers to the original state (of the card), instant_config refers to state at the instant when the effect activates
	CharTargetCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	CharTypeCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	CardTargetCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	CardTypeCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	CardPosCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	AllegianceCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	AttrCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing);
	StatCond(CondConfig& init_config, CondConfig& instant_config, unsigned target_mode, unsigned effect_timing, bool force_nontrivial);
	StatCondVariant(int lower_min, int lower_max, int upper_min, int upper_max);
	IndeCond(CondConfig& init_config, CondConfig& instant_leader_config, unsigned effect_timing); // for conditions that are not associated with a specific card, the config would be associated to leader card though, as leader condition is considered in here
	BaseTargetedEff(CondConfig& self_config, unsigned target_mode, unsigned effect_timing, int effect_depth, bool give_eff);
	BaseUntargetedEff(CondConfig& self_config, unsigned effect_timing, int effect_depth, bool give_eff);
	Destination(CondConfig& self_config, unsigned target_mode, unsigned effect_timing, unsigned dest_mode);
	NewCardVariant(CondConfig& self_config, unsigned target_mode, unsigned effect_timing, int effect_depth);

wrapper: // due to some type system artifact in GIGL, certian parts (e.g. the arguement type in AddExtraEffects) wouldn't work if it is put before the nontermial declaration part
	gigltable<SpecialEffects*> effects_extra;
	void AddExtraEffects(SpecialEffects* effects)
	{
		effects_extra.push_back(effects);
		effects->num_refs++;
	}
	void ClearExtraEffects()
	{
		for (int i = 0; i < effects_extra.size(); i++)
		{
			effects_extra[i]->num_refs--;
			if (effects_extra[i]->num_refs <= 0)
				delete effects_extra[i];
		}
		effects_extra.clear();
	}
	string GetExtraEffectsBrief()
	{
		string tmp_str = "";
		for (int i = 0; i < effects_extra.size(); i++)
			tmp_str += effects_extra[i]->Brief();
		return tmp_str;
	}
	string GetExtraEffectsDetail()
	{
		if (effects_extra.size() == 0)
			return "";

		string tmp_str = "Extra Effects:\n";
		for (int i = 0; i < effects_extra.size(); i++)
			tmp_str += effects_extra[i]->Detail() + "\n";
		return tmp_str;
	}
	string GetExtraEffectsDetailIndent(int indent_size)
	{
		if (effects_extra.size() == 0)
			return "";

		string tmp_str = RepeatSpace(indent_size) + "Extra Effects:\n";
		for (int i = 0; i < effects_extra.size(); i++)
			tmp_str += effects_extra[i]->DetailIndent(indent_size);
		return tmp_str;
	}
	Card* CreateHardCopy(PtrRedirMap& redir_map) // this version share no memory with the source of the copy, it copies everything (internal shared effects are enrepd in the hash map redir_map)
	{
		// cannot directly use the construct statement as we need to pass the item reference for the copy down the function
		Card* card_copy;
		if (config.IsEmpty())
			card_copy = new Card();
		else
			card_copy = new Card(config); // config is needed as the copied card may need to spawn new random card when effect on it is activated, which need the config
		card_copy->root = root->CreateNodeHardCopy(card_copy, redir_map);

		// note: no need to register the contribution counter as this type of copy is only used for AI exploration, which does not count in the actual match contribution
		// note: no need to set the owner/opponent as they must be set after a pair of players are copied
		card_copy->name = name;
		card_copy->is_first_turn_at_field = is_first_turn_at_field;
		card_copy->card_pos = card_pos;
		card_copy->mana = mana;
		card_copy->atk = atk;
		card_copy->max_hp = max_hp;
		card_copy->hp_loss = hp_loss;
		card_copy->max_n_atks = max_n_atks;
		card_copy->n_atks_loss = n_atks_loss;
		card_copy->minion_type = minion_type;
		card_copy->is_charge = is_charge;
		card_copy->is_taunt = is_taunt;
		card_copy->is_stealth = is_stealth;
		card_copy->is_untargetable = is_untargetable;
		card_copy->is_shielded = is_shielded;
		card_copy->is_poisonous = is_poisonous;
		card_copy->is_lifesteal = is_lifesteal;

		for (int i = 0; i < effects_extra.size(); i++) // don't use AddExtraEffects as the num_refs are managed separately
			card_copy->effects_extra.push_back((SpecialEffects*)(effects_extra[i]->CreateNodeHardCopy(card_copy, redir_map))); // using the card_copy as the item reference can be problematic, but we need to make the granted effects to work independent of the original card anyway
		
		return card_copy;
	}
	Card* CreateCopy() // this version shares the effects with the source of the copy, also it resets some attributes such as consumed attack times, is_first_turn_at_field flag etc.
	{
		Card* card_copy;
		SpecialEffects* effects = root->GetEffects();

		switch (card_type)
		{
			case LEADER_CARD:
				card_copy = construct Card(leaderCard(orig_mana, orig_atk, orig_hp, multipleAttack(orig_n_atks),
												justAttributes((orig_is_charge ? (ChargeAttr*)justCharge() : (ChargeAttr*)noCharge()),
																(orig_is_taunt ? (TauntAttr*)justTaunt() : (TauntAttr*)noTaunt()),
																(orig_is_stealth ? (StealthAttr*)justStealth() : (StealthAttr*)noStealth()),
																(orig_is_untargetable ? (UntargetableAttr*)justUntargetable() : (UntargetableAttr*)noUntargetable()),
																(orig_is_shielded ? (ShieldAttr*)justShield() : (ShieldAttr*)noShield()),
																(orig_is_poisonous ? (PoisonousAttr*)justPoisonous() : (PoisonousAttr*)noPoisonous()),
																(orig_is_lifesteal ? (LifestealAttr*)justLifesteal() : (LifestealAttr*)noLifesteal())),
												effects										
												)) with GetDefaultGenConfig(GetRandInt());
				break;
			case MINION_CARD:
				card_copy = construct Card(minionCard(orig_mana, orig_atk, orig_hp, multipleAttack(orig_n_atks),
												(orig_minion_type == BEAST_MINION ? (MinionType*)beastMinion() : (orig_minion_type == DRAGON_MINION ? (MinionType*)dragonMinion() : (MinionType*)demonMinion())),
												justAttributes((orig_is_charge ? (ChargeAttr*)justCharge() : (ChargeAttr*)noCharge()),
																(orig_is_taunt ? (TauntAttr*)justTaunt() : (TauntAttr*)noTaunt()),
																(orig_is_stealth ? (StealthAttr*)justStealth() : (StealthAttr*)noStealth()),
																(orig_is_untargetable ? (UntargetableAttr*)justUntargetable() : (UntargetableAttr*)noUntargetable()),
																(orig_is_shielded ? (ShieldAttr*)justShield() : (ShieldAttr*)noShield()),
																(orig_is_poisonous ? (PoisonousAttr*)justPoisonous() : (PoisonousAttr*)noPoisonous()),
																(orig_is_lifesteal ? (LifestealAttr*)justLifesteal() : (LifestealAttr*)noLifesteal())),
												effects								
												)) with GetDefaultGenConfig(GetRandInt());
				break;
			default:
				card_copy = construct Card(spellCard(orig_mana,
												justAttributes((orig_is_charge ? (ChargeAttr*)justCharge() : (ChargeAttr*)noCharge()),
																(orig_is_taunt ? (TauntAttr*)justTaunt() : (TauntAttr*)noTaunt()),
																(orig_is_stealth ? (StealthAttr*)justStealth() : (StealthAttr*)noStealth()),
																(orig_is_untargetable ? (UntargetableAttr*)justUntargetable() : (UntargetableAttr*)noUntargetable()),
																(orig_is_shielded ? (ShieldAttr*)justShield() : (ShieldAttr*)noShield()),
																(orig_is_poisonous ? (PoisonousAttr*)justPoisonous() : (PoisonousAttr*)noPoisonous()),
																(orig_is_lifesteal ? (LifestealAttr*)justLifesteal() : (LifestealAttr*)noLifesteal())),
												effects									
												)) with GetDefaultGenConfig(GetRandInt());
				break;
		}
		
		effects->num_refs++;

		card_copy->contribution = contribution; // copy the pointer to the counter for contribution
		card_copy->name = name;
		card_copy->owner = owner;
		card_copy->opponent = opponent;
		card_copy->card_pos = card_pos;
		card_copy->mana = mana;
		card_copy->atk = atk;
		card_copy->max_hp = max_hp;
		card_copy->hp_loss = hp_loss; // preserve hp loss
		card_copy->max_n_atks = max_n_atks;
		card_copy->minion_type = minion_type;
		card_copy->is_charge = is_charge;
		card_copy->is_taunt = is_taunt;
		card_copy->is_stealth = is_stealth;
		card_copy->is_untargetable = is_untargetable;
		card_copy->is_shielded = is_shielded;
		card_copy->is_poisonous = is_poisonous;
		card_copy->is_lifesteal = is_lifesteal;

		for (int i = 0; i < effects_extra.size(); i++) // cannot just say card_copy->effects_extra = effects_extra, as the num_refs needs to be properly maintained
			card_copy->AddExtraEffects(effects_extra[i]);
		
		return card_copy;
	}


rule:
	CardRoot
	default:
		{
			preselector
			{
				if (!(global_config & TARGET_IS_LEADER))
					forbid leaderCard;
				if (!(global_config & TARGET_IS_MINION))
					forbid minionCard;
				if (!(global_config & TARGET_IS_SPELL))
					forbid spellCard;
			}
		}
	:=
	| leaderCard: int cost, int attack, int health, AttackTimes* attack_times, Attributes* attributes, SpecialEffects* effects
		{
			card_type = LEADER_CARD;
			generator
			{
				cost = GetRandInt(global_config.min_cost, global_config.max_cost); // currently we only control the cost through the config
				attack = GetRandInt(0, 10);
				health = GetRandInt(10, 40);
			}
			orig_mana = mana = cost;
			orig_atk = atk = attack;
			orig_hp = max_hp = health;
			generator
			{
				CondConfig self_config = GetInitConfigFromCard(item);
				attributes = generate Attributes(self_config, atk);
				if (is_plain)
				{
					attack_times = construct singleAttack();
					effects = construct specialEffects(noTargetedPlayEff(), noOtherEffs());
				}
				else
				{
					attack_times = generate AttackTimes();
					self_config = GetInitConfigFromCard(item); // update for attack times
					effects = generate SpecialEffects(self_config, 0, max_eff_num, 0, false);
				}
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0, <double>{NormalizeCode(cost, 0, 10), NormalizeCode(attack, 0, 10), NormalizeCode(health, 10, 40)}));
				attack_times->FillRep(rep);
				attributes->FillRep(rep);
				effects->FillRep(rep);
			}
			Brief
			{
				return IntToStr(mana) + "/" + IntToStr(atk) + "/" + IntToStr(max_hp - hp_loss) + ", " + IntToStr(max_n_atks - n_atks_loss) + "Attacks" + (IsSleeping() ? "(Sleeping)" : "")
				+ ", Leader. " + attributes->Brief() + " " + effects->Brief() + GetExtraEffectsBrief();
			}
			Detail
			{
				string mana_info = "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ").";
				string atk_info = "ATK: " + IntToStr(atk) + " (originally " + IntToStr(orig_atk) + ").";
				string hp_info = "HP: " + IntToStr(max_hp - hp_loss) + " of " + IntToStr(max_hp) + " (originally " + IntToStr(orig_hp) + ").";
				string atk_times_info = "ATK TIMES: " + IntToStr(max_n_atks - n_atks_loss) + " of " + IntToStr(max_n_atks) + " (originally " + IntToStr(orig_n_atks) + ")";
				string att_times_explain = "";
				if (max_n_atks == 0)
					att_times_explain = " (Cannot attack)";
				else if (max_n_atks > 1)
					att_times_explain = " (Can attack " + IntToStr(max_n_atks) + " times per turn)";
				if (IsSleeping())
					att_times_explain += "(Sleeping).";
				else
					att_times_explain += ".";
				string type_info = "TYPE: Leader (Does not counter-attack).";
				string attr_info = attributes->Detail();
				string effect_info = effects->Detail();
				string extra_effect_info = GetExtraEffectsDetail();
				return mana_info + "\n" + atk_info + "\n" + hp_info + "\n" + atk_times_info + att_times_explain + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			DetailIndent
			{
				string mana_info = RepeatSpace(indent_size) + "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ").";
				string atk_info = RepeatSpace(indent_size) + "ATK: " + IntToStr(atk) + " (originally " + IntToStr(orig_atk) + ").";
				string hp_info = RepeatSpace(indent_size) + "HP: " + IntToStr(max_hp - hp_loss) + " of " + IntToStr(max_hp) + " (originally " + IntToStr(orig_hp) + ").";
				string atk_times_info = RepeatSpace(indent_size) + "ATK TIMES: " + IntToStr(max_n_atks - n_atks_loss) + " of " + IntToStr(max_n_atks) + " (originally " + IntToStr(orig_n_atks) + ")";
				string att_times_explain = "";
				if (max_n_atks == 0)
					att_times_explain = " (Cannot attack)";
				else if (max_n_atks > 1)
					att_times_explain = " (Can attack " + IntToStr(max_n_atks) + " times per turn)";
				if (IsSleeping())
					att_times_explain += "(Sleeping).";
				else
					att_times_explain += ".";
				string type_info = RepeatSpace(indent_size) + "TYPE: Leader (Does not counter-attack).";
				string attr_info = attributes->DetailIndent(indent_size);
				string effect_info = effects->DetailIndent(indent_size);
				string extra_effect_info = GetExtraEffectsDetailIndent(indent_size);
				return mana_info + "\n" + atk_info + "\n" + hp_info + "\n" + atk_times_info + att_times_explain + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			CreateNodeHardCopy = new leaderCard(card_copy, cost, attack, health, 
				(AttackTimes*)(attack_times->CreateNodeHardCopy(card_copy, redir_map)),
				(Attributes*)(attributes->CreateNodeHardCopy(card_copy, redir_map)),
				(SpecialEffects*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffects = effects;
			isTargetedAtPlay
			{
				if (!effects->isTargetedAtPlay(x, y, parent_card))
					return false;

				// check if there is a valid target for battlecry
				for (int i = 0; i <= parent_card->owner->field.size() + parent_card->opponent->field.size() + parent_card->owner->hand.size() + 1; i++)
					if (x != i && effects->CheckPlayValid(x, y, i, parent_card))
						return true;

				// if there is no valid target for battlecry, it also counts as not targeted
				return false;
			}
			CheckPlayValid
			{
				// Check if the target for battlecry is valid when it is targeted, if the play is untargeted (because there's no targeted play effect, or because there is no valid target, or the condition to activate fails), set z to -1
				if (isTargetedAtPlay(x, y, parent_card))
				{
					if (!effects->CheckPlayValid(x, y, z, parent_card))
					{
						#ifndef SUPPRESS_ALL_MSG
						if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
							cout << "Error: Invalid target for the targeted battlecry, while valid target exists." << endl << endl;
						#endif
						return false;
					}
				}
				else
				{
					z = -1;
				}

				return true;
			}
			Play 
			{
				// Play card (replace leader)
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << "The leader card " << parent_card->name << " played and the current leader replaced." << endl << endl;
				#endif
				delete parent_card->owner->leader;
				parent_card->owner->leader = parent_card;
				parent_card->is_first_turn_at_field = true;
				parent_card->card_pos = CARD_POS_AT_LEADER;
				parent_card->IncContribution();

				// Adjusting target index if necessary (the card gets played and the number of minions doesn't increase)
				if (x < z) z--;
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					parent_card->owner->PrintBoard();
				#endif

				// Trigger battlecry
				effects->Play(x, y, z, parent_card);
			}
			Discard
			{
				// Trigger On-discard Effects
				effects->Discard(parent_card);
			}
			CheckAttackValid
			{
				// Check if it can attack
				if (parent_card->n_atks_loss >= parent_card->max_n_atks)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: This leader cannot attack." << endl << endl;
					#endif
					return false;
				}

				// Check if it is sleeping
				if (parent_card->IsSleeping())
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: This leader cannot attack currently, please wait for next turn." << endl << endl;
					#endif
					return false;
				}

				// Check if the target is valid
				if (z <= parent_card->owner->field.size() || z > parent_card->owner->field.size() + parent_card->opponent->field.size() + 1)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Invalid target for attacking." << endl << endl;
					#endif
					return false;
				}

				// Check for taunt and stealth attribute
				Card* target = (z == parent_card->owner->field.size() + parent_card->opponent->field.size() + 1 ? parent_card->opponent->leader : parent_card->opponent->field[z - parent_card->owner->field.size() - 1]);
				if (target->is_stealth)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Stealth characters cannot be attacked." << endl << endl;
					#endif
					return false;
				}
				if (!target->is_taunt)
				{
					for (int i = 0; i < parent_card->opponent->field.size(); i++)
					{
						if (parent_card->opponent->field[i]->is_taunt && !parent_card->opponent->field[i]->is_stealth)
						{
							#ifndef SUPPRESS_ALL_MSG
							if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
								cout << "Error: You must attack a taunt character first." << endl << endl;
							#endif
							return false;
						}
					}
					if (parent_card->opponent->leader->is_taunt && !parent_card->opponent->leader->is_stealth)
					{
						#ifndef SUPPRESS_ALL_MSG
						if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
							cout << "Error: You must attack a taunt character first." << endl << endl;
						#endif
						return false;
					}
				}

				return true;
			}
			Attack
			{
				Card* target = parent_card->owner->GetTargetCard(z);

				/* 
				effects->Attack(x, z, parent_card);
				if (parent_card->owner->ProcessDeferredEvents()) return;
				*/

				if (parent_card->is_stealth)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << " loses stealth." << endl << endl;
					#endif
					parent_card->is_stealth = false;
				}

				// if the target or itself is already being dying before the attack, do not perform the actual attack (well, possily not in actual effect now as there's no on attack effects)
				if (parent_card->is_dying || target->is_dying) return;

				// Perform the actual attack
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << " attacks " << target->owner->name << "\'s " << target->name << "." << endl << endl;
				#endif
				parent_card->n_atks_loss++;								
				target->TakeDamage(atk, parent_card, true);
				if (target->card_type != LEADER_CARD)
					TakeDamage(target->atk, target, !target->is_dying);
			}
			TurnStart { effects->TurnStart(leader, parent_card); }
			TurnEnd { effects->TurnEnd(leader, parent_card); }
			Mutate
			{
				delete attack_times;
				attack_times = generate AttackTimes();
				CondConfig self_config = GetInitConfigFromCard(item);
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
				effects = generate SpecialEffects(self_config, min_eff_n, max_eff_n, effect_depth, false);
			}
			SetOverheatCounts { effects->SetOverheatCounts(val); }
			SetOverheatThresholds { effects->SetOverheatThresholds(val); }
			ModOverheatThresholds { effects->ModOverheatThresholds(amount); }
			destructor
			{
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
			}
		}
	| minionCard: int cost, int attack, int health, AttackTimes* attack_times, MinionType* type, Attributes* attributes, SpecialEffects* effects
		{
			card_type = MINION_CARD;
			generator
			{
				cost = GetRandInt(global_config.min_cost, global_config.max_cost); // currently we only control the cost through the config
				attack = GetRandInt(0, 10);
				health = GetRandInt(1, 10);
			}			
			orig_mana = mana = cost;
			orig_atk = atk = attack;
			orig_hp = max_hp = health;
			generator
			{
				CondConfig self_config = GetInitConfigFromCard(item);
				attributes = generate Attributes(self_config, atk);
				if (is_plain)
				{
					attack_times = construct singleAttack();
					effects = construct specialEffects(noTargetedPlayEff(), noOtherEffs());
				}
				else
				{
					attack_times = generate AttackTimes();
					self_config = GetInitConfigFromCard(item); // update for attack times
					effects = generate SpecialEffects(self_config, 0, max_eff_num, 0, false);
				}
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1, <double>{NormalizeCode(cost, 0, 10), NormalizeCode(attack, 0, 10), NormalizeCode(health, 1, 10)}));
				attack_times->FillRep(rep);
				type->FillRep(rep);
				attributes->FillRep(rep);
				effects->FillRep(rep);
			}
			Brief
			{
				return IntToStr(mana) + "/" + IntToStr(atk) + "/" + IntToStr(max_hp - hp_loss) + ", " + IntToStr(max_n_atks - n_atks_loss) + "Attacks" + (IsSleeping() ? "(Sleeping)" : "")
				+ ", " + MinionTypeDescription(minion_type) + ". " + attributes->Brief() + " " + effects->Brief() + GetExtraEffectsBrief();
			}
			Detail
			{
				string mana_info = "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ").";
				string atk_info = "ATK: " + IntToStr(atk) + " (originally " + IntToStr(orig_atk) + ").";
				string hp_info = "HP: " + IntToStr(max_hp - hp_loss) + " of " + IntToStr(max_hp) + " (originally " + IntToStr(orig_hp) + ").";
				string atk_times_info = "ATK TIMES: " + IntToStr(max_n_atks - n_atks_loss) + " of " + IntToStr(max_n_atks) + " (originally " + IntToStr(orig_n_atks) + ")";
				string att_times_explain = "";
				if (max_n_atks == 0)
					att_times_explain = " (Cannot attack)";
				else if (max_n_atks > 1)
					att_times_explain = " (Can attack " + IntToStr(max_n_atks) + " times per turn)";
				if (IsSleeping())
					att_times_explain += "(Sleeping).";
				else
					att_times_explain += ".";
				string type_info = "TYPE: " + MinionTypeDescription(minion_type) + " (Originally " + MinionTypeDescription(orig_minion_type) + ") Minion."; // note the type may be modified in place
				string attr_info = attributes->Detail();
				string effect_info = effects->Detail();
				string extra_effect_info = GetExtraEffectsDetail();
				return mana_info + "\n" + atk_info + "\n" + hp_info + "\n" + atk_times_info + att_times_explain + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			DetailIndent
			{
				string mana_info = RepeatSpace(indent_size) + "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ").";
				string atk_info = RepeatSpace(indent_size) + "ATK: " + IntToStr(atk) + " (originally " + IntToStr(orig_atk) + ").";
				string hp_info = RepeatSpace(indent_size) + "HP: " + IntToStr(max_hp - hp_loss) + " of " + IntToStr(max_hp) + " (originally " + IntToStr(orig_hp) + ").";
				string atk_times_info = RepeatSpace(indent_size) + "ATK TIMES: " + IntToStr(max_n_atks - n_atks_loss) + " of " + IntToStr(max_n_atks) + " (originally " + IntToStr(orig_n_atks) + ")";
				string att_times_explain = "";
				if (max_n_atks == 0)
					att_times_explain = " (Cannot attack)";
				else if (max_n_atks > 1)
					att_times_explain = " (Can attack " + IntToStr(max_n_atks) + " times per turn)";
				if (IsSleeping())
					att_times_explain += "(Sleeping).";
				else
					att_times_explain += ".";
				string type_info = RepeatSpace(indent_size) + "TYPE: " + MinionTypeDescription(minion_type) + " (Originally " + MinionTypeDescription(orig_minion_type) + ") Minion."; // note the type may be modified in place
				string attr_info = attributes->DetailIndent(indent_size);
				string effect_info = effects->DetailIndent(indent_size);
				string extra_effect_info = GetExtraEffectsDetailIndent(indent_size);
				return mana_info + "\n" + atk_info + "\n" + hp_info + "\n" + atk_times_info + att_times_explain + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			CreateNodeHardCopy = new minionCard(card_copy, cost, attack, health, 
				(AttackTimes*)(attack_times->CreateNodeHardCopy(card_copy, redir_map)),
				(MinionType*)(type->CreateNodeHardCopy(card_copy, redir_map)),
				(Attributes*)(attributes->CreateNodeHardCopy(card_copy, redir_map)),
				(SpecialEffects*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffects = effects;
			isTargetedAtPlay
			{
				if (!effects->isTargetedAtPlay(x, y, parent_card))
					return false;

				// check if there is a valid target for battlecry
				for (int i = 0; i <= parent_card->owner->field.size() + parent_card->opponent->field.size() + parent_card->owner->hand.size() + 1; i++)
					if (x != i && effects->CheckPlayValid(x, y, i, parent_card))
						return true;

				// if there is no valid target for battlecry, it also counts as not targeted
				return false;
			}
			CheckPlayValid
			{
				// Check if the field is full
				if (parent_card->owner->GetActualFieldSize() >= MAX_FIELD_SIZE)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Your field is full." << endl << endl;
					#endif
					return false;
				}

				// Check if the position is valid
				if (y < 0 || y > parent_card->owner->field.size())
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Invalid position." << endl << endl;
					#endif
					return false;
				}

				// Check if the target for battlecry is valid when it is targeted, if the play is untargeted (because there's no targeted play effect, or because there is no valid target, or the condition to activate fails), set z to -1
				if (isTargetedAtPlay(x, y, parent_card))
				{
					if (!effects->CheckPlayValid(x, y, z, parent_card))
					{
						#ifndef SUPPRESS_ALL_MSG
						if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
							cout << "Error: Invalid target for the targeted battlecry, while valid target exists." << endl << endl;
						#endif
						return false;
					}
				}
				else
				{
					z = -1;
				}

				return true;
			}
			Play 
			{
				// Play card (place minion)
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << "The minion card " << parent_card->name << " played." << endl << endl;
				#endif
				owner->field.insert(parent_card->owner->field.begin() + y, parent_card);
				parent_card->is_first_turn_at_field = true;
				parent_card->card_pos = CARD_POS_AT_FIELD;
				parent_card->IncContribution();

				// Adjusting target index if necessary (the card gets played and the minion is inserted)
				if (y < z && z < x) z++;
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					parent_card->owner->PrintBoard();
				#endif

				// Trigger battlecry
				effects->Play(x, y, z, parent_card);
			}
			Destroy
			{
				// Trigger Deathrattle
				effects->Destroy(parent_card);
			}
			Discard
			{
				// Trigger On-discard Effects
				effects->Discard(parent_card);
			}
			CheckAttackValid
			{
				// Check if it can attack
				if (parent_card->n_atks_loss >= parent_card->max_n_atks)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: This minion cannot attack currently." << endl << endl;
					#endif
					return false;
				}

				// Check if it is sleeping
				if (parent_card->IsSleeping())
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: This minion cannot attack currently, please wait for next turn." << endl << endl;
					#endif
					return false;
				}

				// Check if the target is valid
				if (z <= parent_card->owner->field.size() || z > parent_card->owner->field.size() + parent_card->opponent->field.size() + 1)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Invalid target for attacking." << endl << endl;
					#endif
					return false;
				}

				// Check for taunt and stealth attribute
				Card* target = (z == parent_card->owner->field.size() + parent_card->opponent->field.size() + 1 ? parent_card->opponent->leader : parent_card->opponent->field[z - parent_card->owner->field.size() - 1]);
				if (target->is_stealth)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Stealth characters cannot be attacked." << endl << endl;
					#endif
					return false;
				}
				if (!target->is_taunt)
				{
					for (int i = 0; i < parent_card->opponent->field.size(); i++)
					{
						if (parent_card->opponent->field[i]->is_taunt && !parent_card->opponent->field[i]->is_stealth)
						{
							#ifndef SUPPRESS_ALL_MSG
							if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
								cout << "Error: You must attack a taunt character first." << endl << endl;
							#endif
							return false;
						}
					}
					if (parent_card->opponent->leader->is_taunt && !parent_card->opponent->leader->is_stealth)
					{
						#ifndef SUPPRESS_ALL_MSG
						if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
							cout << "Error: You must attack a taunt character first." << endl << endl;
						#endif
						return false;
					}
				}

				return true;
			}
			Attack
			{
				Card* target = parent_card->owner->GetTargetCard(z);

				/* 
				effects->Attack(x, z, parent_card);
				if (parent_card->owner->ProcessDeferredEvents()) return;
				*/

				if (parent_card->is_stealth)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << " loses stealth." << endl << endl;
					#endif
					parent_card->is_stealth = false;
				}

				// if the target or itself is already dying before the attack, do not perform the actual attack (well, possily not in actual effect now as there's no on attack effects)
				if (parent_card->is_dying || target->is_dying) return;

				// Perform the actual attack
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << " attacks " << target->owner->name << "\'s " << target->name << "." << endl << endl;
				#endif
				parent_card->n_atks_loss++;								
				target->TakeDamage(atk, parent_card, true);
				if (target->card_type != LEADER_CARD)
					TakeDamage(target->atk, target, !target->is_dying);
			}
			TurnStart { effects->TurnStart(leader, parent_card); }
			TurnEnd { effects->TurnEnd(leader, parent_card); }
			Mutate
			{
				delete attack_times;
				attack_times = generate AttackTimes();
				CondConfig self_config = GetInitConfigFromCard(item);
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
				effects = generate SpecialEffects(self_config, min_eff_n, max_eff_n, effect_depth, false);
			}
			SetOverheatCounts { effects->SetOverheatCounts(val); }
			SetOverheatThresholds { effects->SetOverheatThresholds(val); }
			ModOverheatThresholds { effects->ModOverheatThresholds(amount); }
			destructor
			{
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
			}
		}
	| spellCard: int cost, Attributes* attributes, SpecialEffects* effects
		{
			card_type = SPELL_CARD;
			generator
			{
				cost = GetRandInt(global_config.min_cost, global_config.max_cost); // currently we only control the cost through the config
			}
			orig_mana = mana = cost;
			generator
			{
				CondConfig self_config = GetInitConfigFromCard(item);
				attributes = generate Attributes(self_config, -1); // -1 means not applicable
				if (is_plain)
					effects = construct specialEffects(noTargetedPlayEff(), noOtherEffs());
				else
					effects = generate SpecialEffects(self_config, 1, max_eff_num, 0, false);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2, <double>{NormalizeCode(cost, 0, 10)}));
				attributes->FillRep(rep);
				effects->FillRep(rep);
			}
			Brief
			{
				return IntToStr(mana) + " Mana Spell. " + attributes->Brief() + " " + effects->Brief() + GetExtraEffectsBrief();
			}
			Detail
			{
				string mana_info = "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ")";
				string type_info = "TYPE: Spell.";
				string attr_info = attributes->Detail();
				string effect_info = effects->Detail();
				string extra_effect_info = GetExtraEffectsDetail();
				return mana_info + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			DetailIndent
			{
				string mana_info = RepeatSpace(indent_size) + "MANA: " + IntToStr(mana) + " (originally " + IntToStr(orig_mana) + ")";
				string type_info = RepeatSpace(indent_size) + "TYPE: Spell.";
				string attr_info = attributes->DetailIndent(indent_size);
				string effect_info = effects->DetailIndent(indent_size);
				string extra_effect_info = GetExtraEffectsDetailIndent(indent_size);
				return mana_info + "\n" + type_info + "\n" + attr_info + effect_info + extra_effect_info;
			}
			CreateNodeHardCopy = new spellCard(card_copy, cost,
				(Attributes*)(attributes->CreateNodeHardCopy(card_copy, redir_map)),
				(SpecialEffects*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffects = effects;
			isTargetedAtPlay
			{
				return effects->isTargetedAtPlay(x, y, parent_card);
			}
			CheckPlayValid
			{
				// Check if the target for the spell is valid, if not return false
				if (isTargetedAtPlay(x, y, parent_card) && !effects->CheckPlayValid(x, y, z, parent_card))
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration && !parent_card->owner->is_guest)
						cout << "Error: Invalid target for the targeted spell." << endl << endl;
					#endif
					return false;
				}

				return true;
			}
			Play
			{
				// Play card (play spell)
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << "The spell card " << parent_card->name << " played." << endl << endl;
				#endif

				// Mark the card for deletion
				parent_card->owner->FlagCastSpell(parent_card, true);

				// Trigger effects
				effects->Play(x, y, z, parent_card);
			}
			Discard
			{
				// Trigger On-discard Effects
				effects->Discard(parent_card);
			}
			TurnStart { effects->TurnStart(leader, parent_card); }
			TurnEnd { effects->TurnEnd(leader, parent_card); }
			Mutate
			{
				CondConfig self_config = GetInitConfigFromCard(item);
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
				effects = generate SpecialEffects(self_config, (min_eff_n > 1 ? min_eff_n : 1), max_eff_n, effect_depth, false); // spell has to at least have one effect
			}
			SetOverheatCounts { effects->SetOverheatCounts(val); }
			SetOverheatThresholds { effects->SetOverheatThresholds(val); }
			ModOverheatThresholds { effects->ModOverheatThresholds(amount); }
			destructor
			{
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
			}
		}
		
	AttackTimes :=
	| zeroAttack:
		{
			orig_n_atks = max_n_atks = 0;
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new zeroAttack(card_copy);	
		}
	| singleAttack:
		{
			orig_n_atks = max_n_atks = 1;
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new singleAttack(card_copy);
		}
	| multipleAttack: int n_atks
		{
			generator { n_atks = 100 / GetRandInt(17, 50); } // 2 ~ 5 but not evenly distributed
			n_atks_loss = 0;
			orig_n_atks = max_n_atks = n_atks;
			FillRep
			{
				rep.push_back(mkNodeRep(2, <double>{NormalizeCode(n_atks, 0, 5)})); // not using the range of 2 ~ 5 for normalization for more consistent encoding considering the recursive nn version
			}
			CreateNodeHardCopy = new multipleAttack(card_copy, n_atks);
		}

	MinionType :=
	| beastMinion:
		{
			orig_minion_type = minion_type = BEAST_MINION;
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new beastMinion(card_copy);
		}
	| dragonMinion:
		{
			orig_minion_type = minion_type = DRAGON_MINION;
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new dragonMinion(card_copy);
		}
	| demonMinion:
		{
			orig_minion_type = minion_type = DEMON_MINION;
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			CreateNodeHardCopy = new demonMinion(card_copy);
		}

	Attributes :=
	| justAttributes: ChargeAttr* c, TauntAttr* t, StealthAttr* s, UntargetableAttr* u, ShieldAttr* d, PoisonousAttr* p, LifestealAttr* l
		{
			generator
			{
				c = generate ChargeAttr(self_config);
				t = generate TauntAttr(self_config);
				s = generate StealthAttr(self_config);
				u = generate UntargetableAttr(self_config);
				d = generate ShieldAttr(self_config);
				p = generate PoisonousAttr(self_config, damage);
				l = generate LifestealAttr(self_config, damage);
			}
			FillRep
			{
				// this is just a pass-down node
				c->FillRep(rep);
				t->FillRep(rep);
				s->FillRep(rep);
				u->FillRep(rep);
				d->FillRep(rep);
				p->FillRep(rep);
				l->FillRep(rep);
			}
			Brief = AttributeDescriptionBrief(is_charge, is_taunt, is_stealth, is_untargetable, is_shielded, is_poisonous, is_lifesteal);
			Detail
			{
				string cur_info = AttributeDescriptionDetail(is_charge, is_taunt, is_stealth, is_untargetable, is_shielded, is_poisonous, is_lifesteal, 0); // note the attributes may be modified in place
				string orig_info = AttributeDescriptionBrief(orig_is_charge, orig_is_taunt, orig_is_stealth, orig_is_untargetable, orig_is_shielded, orig_is_poisonous, orig_is_lifesteal);
				if (cur_info.length() == 0 && orig_info.length() == 0)
					return "";
				return (cur_info.length() == 0 ? "No Attribute " : cur_info) + "(Originally " + (orig_info.length() == 0 ? "No Attribute" : orig_info) + ")\n";
			}
			DetailIndent
			{
				string cur_info = AttributeDescriptionDetail(is_charge, is_taunt, is_stealth, is_untargetable, is_shielded, is_poisonous, is_lifesteal, indent_size); // note the attributes may be modified in place
				string orig_info = AttributeDescriptionBrief(orig_is_charge, orig_is_taunt, orig_is_stealth, orig_is_untargetable, orig_is_shielded, orig_is_poisonous, orig_is_lifesteal);
				if (cur_info.length() == 0 && orig_info.length() == 0)
					return "";
				return RepeatSpace(indent_size) + (cur_info.length() == 0 ? "No Attribute " : cur_info) + "(Originally " + (orig_info.length() == 0 ? "No Attribute" : orig_info) + ")\n";
			}
			CreateNodeHardCopy = new justAttributes(card_copy,
				(ChargeAttr*)(c->CreateNodeHardCopy(card_copy, redir_map)),
				(TauntAttr*)(t->CreateNodeHardCopy(card_copy, redir_map)),
				(StealthAttr*)(s->CreateNodeHardCopy(card_copy, redir_map)),
				(UntargetableAttr*)(u->CreateNodeHardCopy(card_copy, redir_map)),
				(ShieldAttr*)(d->CreateNodeHardCopy(card_copy, redir_map)),
				(PoisonousAttr*)(p->CreateNodeHardCopy(card_copy, redir_map)),
				(LifestealAttr*)(l->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = c->GetInitAttrFlag() | t->GetInitAttrFlag() | s->GetInitAttrFlag() | u->GetInitAttrFlag() | d->GetInitAttrFlag() | p->GetInitAttrFlag() | l->GetInitAttrFlag(); // currently not used
		}

	DamageAttributes := // this doesn't need description, just contributing to attributes
	| damageAttributes: PoisonousAttr* p, LifestealAttr* l
		{
			generator
			{
				if (target_mode == TARGET_MODE_LEADER || (target_mode == TARGET_MODE_SELF && !(self_config & TARGET_NOT_LEADER))) // damage towards leader shouldn't have poisonous attributes
					p = construct noPoisonous();
				else
					p = generate PoisonousAttr(self_config, damage);
				l = generate LifestealAttr(self_config, damage);
			}
			FillRep
			{
				// this is just a pass-down node
				p->FillRep(rep);
				l->FillRep(rep);
			}
			CreateNodeHardCopy = new damageAttributes(card_copy,
				(PoisonousAttr*)(p->CreateNodeHardCopy(card_copy, redir_map)),
				(LifestealAttr*)(l->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = p->GetInitAttrFlag() | l->GetInitAttrFlag();
		}

	ChargeAttr
	default:
		{
			preselector
			{
				if (self_config & TARGET_IS_SPELL)
					force noCharge;
			}
		}
	:=
	| noCharge: 
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noCharge(card_copy);
		}
	| justCharge:
		{ 
			orig_is_charge = is_charge = true;
			generator { self_config |= TARGET_IS_CHARGE; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justCharge(card_copy);
			GetInitAttrFlag = TARGET_IS_CHARGE;
		}
		
	TauntAttr
	default:
		{
			preselector
			{
				if (self_config & TARGET_IS_SPELL)
					force noTaunt;
			}
		}
	:=
	| noTaunt:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noTaunt(card_copy);
		}
	| justTaunt: 
		{
			orig_is_taunt = is_taunt = true;
			generator { self_config |= TARGET_IS_TAUNT; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justTaunt(card_copy);
			GetInitAttrFlag = TARGET_IS_TAUNT;
		}

	StealthAttr
	default:
		{
			preselector
			{
				if (self_config & (TARGET_IS_LEADER | TARGET_IS_SPELL)) // leaders never get generated with stealth (otherwise too OP)
					force noStealth;
			}
		}
	:=
	| noStealth:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noStealth(card_copy);
		}
	| justStealth:
		{
			orig_is_stealth = is_stealth = true;
			generator { self_config |= TARGET_IS_STEALTH; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justStealth(card_copy);
			GetInitAttrFlag = TARGET_IS_STEALTH;
		}

	UntargetableAttr :=
	| noUntargetable:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noUntargetable(card_copy);
		}
	| justUntargetable:
		{
			orig_is_untargetable = is_untargetable = true;
			generator { self_config |= TARGET_IS_UNTARGETABLE; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justUntargetable(card_copy);
			GetInitAttrFlag = TARGET_IS_UNTARGETABLE;
		}

	ShieldAttr
	default:
		{
			preselector
			{
				if (self_config & TARGET_IS_SPELL)
					force noShield;
			}
		}
	:=
	| noShield:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noShield(card_copy);
		}
	| justShield:
		{
			orig_is_shielded = is_shielded = true;
			generator { self_config |= TARGET_IS_SHIELDED; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justShield(card_copy);
			GetInitAttrFlag = TARGET_IS_SHIELDED;
		}

	PoisonousAttr
	default:
		{
			preselector
			{
				if (damage < 0 || (self_config & TARGET_IS_POISONOUS)) // negative damage means not applicable; the other condition applies to two cases (mainly for the latter one): 1. it already had the attribute, so it doesn't matter; 2. previous effect has source condition of it, so to avoid making it trivial, don't add the attribute
					force noPoisonous;
			}
		}
	:=
	| noPoisonous:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noPoisonous(card_copy);
		}
	| justPoisonous:
		{
			orig_is_poisonous = is_poisonous = true;
			generator { self_config |= TARGET_IS_POISONOUS; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justPoisonous(card_copy);
			GetInitAttrFlag = TARGET_IS_POISONOUS;
		}

	LifestealAttr
	default:
		{
			preselector
			{
				if (damage < 0 || (self_config & TARGET_IS_LIFESTEAL)) // negative damage means not applicable; the other condition applies to two cases (mainly for the latter one): 1. it already had the attribute, so it doesn't matter; 2. previous effect has source condition of it, so to avoid making it trivial, don't add the attribute
					force noLifesteal;
			}
		}
	:=
	| noLifesteal:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			CreateNodeHardCopy = new noLifesteal(card_copy);
		}
	| justLifesteal:
		{ 
			orig_is_lifesteal = is_lifesteal = true;
			generator { self_config |= TARGET_IS_LIFESTEAL; }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			CreateNodeHardCopy = new justLifesteal(card_copy);
			GetInitAttrFlag = TARGET_IS_LIFESTEAL;
		}

	SpecialEffects
	default:
		{
			pregencontor
			{
				num_refs = 1;
			}
		}
	:=
	| specialEffects: TargetedPlayEff* effect, OtherEffs* effects // only one targeted effect per category is allowed, 
		{
			generator
			{
				effect = generate TargetedPlayEff(self_config, effect_depth, give_eff);
				int l_num = effect->GetEffectNum(); // note implicit child generation is added before these
				self_config &= ExtractEffectIndependentConfig(effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT));
				effects = generate OtherEffs(self_config, min_n - l_num, max_n - l_num, effect_depth, give_eff);
			}
			FillRep
			{
				// this is just a pass-down node
				effect->FillRep(rep);
				effects->FillRep(rep);
			}
			Brief = effect->Brief() + effects->Brief();
			Detail = effect->Detail() + effects->Detail();
			DetailIndent = effect->DetailIndent(indent_size) + effects->DetailIndent(indent_size);
			CreateNodeHardCopy
			{
				SpecialEffects* effects_copy = nullptr;
				if (num_refs <= 1)
				{
					effects_copy = new specialEffects(card_copy,
						(TargetedPlayEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
						(OtherEffs*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
					effects_copy->num_refs = num_refs;
				}
				else
				{
					void* tmp_key = (void*)this;
					PtrRedirMapIter it = redir_map.find(tmp_key);
					if (it == redir_map.end()) // not found
					{
						effects_copy = new specialEffects(card_copy,
							(TargetedPlayEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
							(OtherEffs*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
						redir_map[tmp_key] = effects_copy;
					}
					else // found
					{
						effects_copy = (SpecialEffects*)(it->second);
						effects_copy->num_refs++;
					}
				}
				
				return effects_copy;
			}
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT);
				tmp_config &= effects->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT);
				return tmp_config;
			}
			isTargetedAtPlay = effect->isTargetedAtPlay(x, y, parent_card);
			CheckPlayValid = effect->CheckPlayValid(x, y, z, parent_card);
			Play { effect->Play(x, y, z, parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->Play(x, y, z, parent_card); }
			Destroy { effects->Destroy(parent_card); }
			Discard { effects->Discard(parent_card); }
			TurnStart { effects->TurnStart(leader, parent_card); }
			TurnEnd { effects->TurnEnd(leader, parent_card); }
			SetOverheatCounts { effect->SetOverheatCounts(val); effects->SetOverheatCounts(val);}
			SetOverheatThresholds { effect->SetOverheatThresholds(val); effects->SetOverheatThresholds(val);}
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); effects->ModOverheatThresholds(amount); }
		}
	
	TargetedPlayEff
	default:
		{
			preselector
			{
				// targeted effects on played leaders are never generated through recursive generation path, so there shouldn't need to be extra check for played leaders
				if (give_eff)
					force noTargetedPlayEff;
				if (!(self_config & TARGET_ANY_CHAR))
					forbid targetedBattlecryEff;
				if (!(self_config & TARGET_IS_SPELL))
					forbid targetedCastEff;
			}
		}
	:=
	| noTargetedPlayEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			DetailIndent = ""; // avoid having extra spaces
			CreateNodeHardCopy = new noTargetedPlayEff(card_copy);
		}
	| targetedBattlecryEff: TargetedEff* effect
		{
			generator
			{
				self_config &= CHAR_COND_FILTER;
				effect = generate TargetedEff(self_config, EFFECT_TIMING_PLAY, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
			}
			Brief = "<Battlecry" + effect->Brief() + ">";
			Detail = "Battlecry: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Battlecry: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new targetedBattlecryEff(card_copy, (TargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffectNum = 1;
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_PLAY);
				tmp_config &= CHAR_COND_FILTER;
				// leader and field shall not be selected at the same time if giving a battlecry (leader card is special in that they cannot change their place anymore after being placed)
				if (!(self_config & TARGET_POS_HAND_OR_DECK) || !(tmp_config & TARGET_POS_HAND_OR_DECK))
					tmp_config &= NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER) || !(tmp_config & TARGET_NOT_LEADER)) 
					tmp_config &= HAND_OR_DECK_COND_FILTER;
				else
					tmp_config &= (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				return tmp_config;
			}
			isTargetedAtPlay = effect->isTargetedAtPlay(x, y, parent_card); // battlecries and spell become untargeted if the condition for it to activate fails (for spells it is different from no valid target in which case the spell cannot be played)
			CheckPlayValid = effect->CheckPlayValid(x, y, z, parent_card);
			Play
			{
				if (z >= 0)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s battlecry effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
					#endif
					effect->TargetedAction(z, parent_card, true); // negative means no valid target and ignored
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << endl;
					#endif
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)				
						cout << "Note: condition failed or overheated or no valid target, target ignored, and battlecry not triggered." << endl;
				#endif			
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| targetedCastEff: TargetedEff* effect
		{
			generator
			{
				self_config &= SPELL_COND_FILTER;
				effect = generate TargetedEff(self_config, EFFECT_TIMING_PLAY, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				effect->FillRep(rep);
			}
			Brief = "<Cast" + effect->Brief() + ">";
			Detail = "Cast: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Cast: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new targetedCastEff(card_copy, (TargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffectNum = 1;
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_PLAY);
				tmp_config &= SPELL_COND_FILTER;
				return tmp_config;
			}
			isTargetedAtPlay = effect->isTargetedAtPlay(x, y, parent_card); // battlecries and spell become untargeted if the condition for it to activate fails (for spells it is different from no valid target in which case the spell cannot be played)
			CheckPlayValid = effect->CheckPlayValid(x, y, z, parent_card);
			Play
			{
				if (z >= 0)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s spell cast effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
					#endif
					effect->TargetedAction(z, parent_card, true); // negative means no valid target and ignored
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << endl;
					#endif
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Note: condition failed or overheated or no valid target, target ignored, and cast effect not triggered." << endl;
				#endif			
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}	

	OtherEffs
	default:
		{
			preselector
			{
				if (min_n > 0) // this takes precedence as the lower bound is often some constant (0, or 1) while the upper bound may be accidentally smaller than the lower bound if computed by some formula
					force consOtherEffs;
				if (max_n <= 0)
					force noOtherEffs;
			}
		}
	:=
	| noOtherEffs:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			DetailIndent = ""; // avoid having extra spaces
			CreateNodeHardCopy = new noOtherEffs(card_copy);
		}
	| consOtherEffs: OtherEff* effect, OtherEffs* effects
		{
			generator
			{ 
				effect = generate OtherEff(self_config, effect_depth, give_eff);
				self_config &= ExtractEffectIndependentConfig(effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT));
				effects = generate OtherEffs(self_config, min_n - 1, max_n - 1, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
				effects->FillRep(rep);
			}
			Brief = effect->Brief() + effects->Brief();
			Detail = effect->Detail() + effects->Detail();
			DetailIndent = effect->DetailIndent(indent_size) + effects->DetailIndent(indent_size);
			CreateNodeHardCopy = new consOtherEffs(card_copy,
				(OtherEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(OtherEffs*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
			GetEffectNum = 1 + effects->GetEffectNum(); // currently not used
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT);
				tmp_config &= effects->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DEFAULT);
				return tmp_config;
			}
			Play { effect->Play(x, y, z, parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->Play(x, y, z, parent_card); } // if this minion dies in the middle of multiple battlecries, the latter ones does not gets activated, similar below except deathrattle
			Destroy { effect->Destroy(parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->Destroy(parent_card); }
			Discard { effect->Discard(parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->Discard(parent_card); }
			TurnStart { effect->TurnStart(leader, parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->TurnStart(leader, parent_card); }
			TurnEnd { effect->TurnEnd(leader, parent_card); if (parent_card->owner->ProcessDeferredEvents()) return; effects->TurnEnd(leader, parent_card); }
			SetOverheatCounts { effect->SetOverheatCounts(val); effects->SetOverheatCounts(val);}
			SetOverheatThresholds { effect->SetOverheatThresholds(val); effects->SetOverheatThresholds(val);}
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); effects->ModOverheatThresholds(amount); }
		}
	
	OtherEff
	default:
		{
			preselector
			{
				if (!(self_config & TARGET_ANY_CHAR))
					forbid untargetedBattlecryEff;
				if (!(self_config & TARGET_IS_SPELL))
					forbid untargetedCastEff;
				if (!(self_config & TARGET_IS_MINION))
					forbid deathrattleEff;
				if (!(self_config & TARGET_NOT_LEADER) && !(self_config & TARGET_POS_HAND_OR_DECK)) // played leaders should not be granted battlecry effects
					forbid untargetedBattlecryEff, onDiscardEff;
			}
		}
	:=
	| untargetedBattlecryEff: UntargetedEff* effect
		{
			generator
			{
				self_config &= CHAR_COND_FILTER;
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_PLAY, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				effect->FillRep(rep);
			}
			Brief = "<Battlecry" + effect->Brief() + ">";
			Detail = "Battlecry: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Battlecry: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new untargetedBattlecryEff(card_copy, (UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_PLAY);
				tmp_config &= CHAR_COND_FILTER;
				// leader and field shall not be selected at the same time if giving a battlecry (leader card is special in that they cannot change their place anymore after being placed)
				if (!(self_config & TARGET_POS_HAND_OR_DECK) || !(tmp_config & TARGET_POS_HAND_OR_DECK))
					tmp_config &= NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER) || !(tmp_config & TARGET_NOT_LEADER)) 
					tmp_config &= HAND_OR_DECK_COND_FILTER;
				else
					tmp_config &= (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				return tmp_config;
			}
			Play 
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s battlecry effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
				#endif
				effect->UntargetedAction(parent_card);
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << endl;
				#endif
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| untargetedCastEff: UntargetedEff* effect
		{
			generator
			{
				self_config &= SPELL_COND_FILTER;
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_PLAY, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
			}
			Brief = "<Cast" + effect->Brief() + ">";
			Detail = "Cast: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Cast: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new untargetedCastEff(card_copy, (UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_PLAY);
				tmp_config &= SPELL_COND_FILTER;
				return tmp_config;
			}
			Play 
			{ 
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s spell effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
				#endif
				effect->UntargetedAction(parent_card);
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << endl;
				#endif
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| deathrattleEff: UntargetedEff* effect
		{
			generator
			{
				self_config &= MINION_COND_FILTER; 
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_DESTROY, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				effect->FillRep(rep);
			}
			Brief = "<Deathrattle" + effect->Brief() + ">";
			Detail = "Deathrattle: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Deathrattle: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new deathrattleEff(card_copy, (UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DESTROY);
				tmp_config &= MINION_COND_FILTER;
				return tmp_config;
			}
			Destroy
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s deathrattle effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
				#endif
				effect->UntargetedAction(parent_card);
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << endl;
				#endif
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| onDiscardEff: UntargetedEff* effect
		{
			generator
			{ 
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_DISCARD, effect_depth, give_eff);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(3));
				effect->FillRep(rep);
			}
			Brief = "<Discard" + effect->Brief() + ">";
			Detail = "Discard: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "Discard: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new onDiscardEff(card_copy, (UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_DISCARD);
				// leader and field shall not be selected at the same time if giving a on-discard effect (leader card is special in that they cannot change their place anymore after being placed)
				if (!(self_config & TARGET_POS_HAND_OR_DECK) || !(tmp_config & TARGET_POS_HAND_OR_DECK))
					tmp_config &= NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER) || !(tmp_config & TARGET_NOT_LEADER)) 
					tmp_config &= HAND_OR_DECK_COND_FILTER;
				else
					tmp_config &= (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				return tmp_config;
			}
			Discard
			{
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s on-discard effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
				#endif
				effect->UntargetedAction(parent_card);
				#ifndef SUPPRESS_ALL_MSG
				if (!parent_card->owner->is_exploration)
					cout << endl;
				#endif
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| turnStartEff: UntargetedEff* effect, AllegianceCond* alle
		{
			generator
			{
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_TURN, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, EFFECT_TIMING_TURN);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4));
				effect->FillRep(rep);
				alle->FillRep(rep);
			}
			Brief = "<Trigger" + effect->Brief() + ">";
			Detail = "At the start of " + alle->DetailAlt2() + "turns: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "At the start of " + alle->DetailAlt2() + "turns: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new turnStartEff(card_copy,
				(UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_TURN);
			TurnStart 
			{ 
				if (alle->CheckCardValid(leader, parent_card))
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s turn start effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
					#endif
					effect->UntargetedAction(parent_card);
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << endl;
					#endif
				}
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}
	| turnEndEff: UntargetedEff* effect, AllegianceCond* alle
		{
			generator
			{
				effect = generate UntargetedEff(self_config, EFFECT_TIMING_TURN, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, EFFECT_TIMING_TURN);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(5));
				effect->FillRep(rep);
				alle->FillRep(rep);
			}
			Brief = "<Trigger" + effect->Brief() + ">";
			Detail = "At the end of " + alle->DetailAlt2() + "turns: " + effect->Detail() + "." + effect->Postfix();
			DetailIndent = RepeatSpace(indent_size) + "At the end of " + alle->DetailAlt2() + "turns: " + effect->Detail() + "." + effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new turnEndEff(card_copy,
				(UntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig = effect->GetGlobalSelfConfig(self_config, EFFECT_TIMING_TURN);
			TurnEnd 
			{ 
				if (alle->CheckCardValid(leader, parent_card))
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << parent_card->owner->name << "\'s " << parent_card->name << "\'s turn end effect activated: " << effect->Detail() << "." << effect->PostfixIndent(4);
					#endif
					effect->UntargetedAction(parent_card);
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << endl;
					#endif
				}
			}
			SetOverheatCounts { effect->SetOverheatCounts(val); }
			SetOverheatThresholds { effect->SetOverheatThresholds(val); }
			ModOverheatThresholds { effect->ModOverheatThresholds(amount); }
		}

	TargetedEff // currently the destination only has a constraint (not a condition to trigger effect), and other different types of conditions does not appear together with each other (similar for untargeted one)
	default:
		{
			preselector
			{
				if ((self_config & TARGET_IS_SPELL) // as spell position at play is questionable we simply don't allow this sort of conditions
					|| (!(self_config & TARGET_NOT_LEADER) && effect_timing == EFFECT_TIMING_PLAY)) // the source condition on leaders (as characters) at play is not needed as it can be covered by leader condition
					forbid srcCondTargetedEff;
			}
		}
	:=
	| noCondTargetedEff: BaseTargetedEff* effect, TargetCond* desconstr
		{
			generator
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				if (!(self_config & TARGET_IS_SPELL))
					effect_timing_filter = PLAY_CHAR_SRC_FILTER;
				else if (!(self_config & TARGET_ANY_CHAR))
					effect_timing_filter = PLAY_SPELL_SRC_FILTER;

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;				
				effect = generate BaseTargetedEff(self_config_copy, TARGET_MODE_PLAY, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetPlayTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				desconstr = generate TargetCond(tmp_init_config, tmp_config, TARGET_MODE_PLAY, effect_timing); 
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				effect->FillRep(rep);
				desconstr->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy
			{
				noCondTargetedEff* effect_copy = new noCondTargetedEff(card_copy,
					(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
					(TargetCond*)(desconstr->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}	
			isTargetedAtPlay = overheat_count < overheat_threshold;
			CheckPlayValid
			{
				// check for untargetable and stealth attributes
				if (parent_card->owner->IsValidTarget(z))
				{
					Card* card = parent_card->owner->GetTargetCard(z);
					if (card->is_untargetable || (card->is_stealth && parent_card->owner->IsValidCharTarget(z)))
						return false;
				}
				else
					return false;

				return desconstr->CheckPlayValid(x, y, z, parent_card);
			}
			TargetedAction
			{
				if (overheat_count < overheat_threshold)
				{
					overheat_count++;
					parent_card->IncContribution();
					return effect->TargetedAction(z, parent_card, true);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Overheated, not actually activated." << endl;
				#endif

				return false;
			}
		}
	| indeCondTargetedEff: BaseTargetedEff* effect, TargetCond* desconstr, IndeCond* cond
		{
			generator
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				if (!(self_config & TARGET_IS_SPELL))
					effect_timing_filter = PLAY_CHAR_SRC_FILTER;
				else if (!(self_config & TARGET_ANY_CHAR))
					effect_timing_filter = PLAY_SPELL_SRC_FILTER;

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;
				effect = generate BaseTargetedEff(self_config_copy, TARGET_MODE_PLAY, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetPlayTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				desconstr = generate TargetCond(tmp_init_config, tmp_config, TARGET_MODE_PLAY, effect_timing);
				cond = generate IndeCond(tmp_init_config = GetDefaultInitConfig(), tmp_config = GetDefaultConfig(), effect_timing); // reinitialize the configs as the target should not affect the independ cond
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
				desconstr->FillRep(rep);
				cond->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix() + ", if " + cond->Detail();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix() + ", if " + cond->Detail();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy
			{
				indeCondTargetedEff* effect_copy = new indeCondTargetedEff(card_copy,
					(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
					(TargetCond*)(desconstr->CreateNodeHardCopy(card_copy, redir_map)),
					(IndeCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}
			isTargetedAtPlay = overheat_count < overheat_threshold && cond->CheckThisValid(parent_card);
			CheckPlayValid
			{
				// check for untargetable and stealth attributes
				if (parent_card->owner->IsValidTarget(z))
				{
					Card* card = parent_card->owner->GetTargetCard(z);
					if (card->is_untargetable || (card->is_stealth && parent_card->owner->IsValidCharTarget(z)))
						return false;
				}
				else
					return false;

				return desconstr->CheckPlayValid(x, y, z, parent_card);
			}
			TargetedAction
			{ 
				if (cond->CheckThisValid(parent_card) && overheat_count < overheat_threshold)
				{
					overheat_count++;
					parent_card->IncContribution();
					return effect->TargetedAction(z, parent_card, true);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Condition check failed or overheated, not actually activated." << endl;
				#endif
				return false;
			}
		}
	| srcCondTargetedEff: BaseTargetedEff* effect, TargetCond* desconstr, TargetCond* srccond
		{
			generator
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				if (!(self_config & TARGET_IS_SPELL))
					effect_timing_filter = PLAY_CHAR_SRC_FILTER;
				else if (!(self_config & TARGET_ANY_CHAR))
					effect_timing_filter = PLAY_SPELL_SRC_FILTER;

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;
				effect = generate BaseTargetedEff(self_config_copy, TARGET_MODE_PLAY, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetPlayTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				desconstr = generate TargetCond(tmp_init_config, tmp_config, TARGET_MODE_PLAY, effect_timing);
				srccond = generate TargetCond(self_config_copy, tmp_config = GetFlagConfig(effect_timing_filter), TARGET_MODE_SOURCE, effect_timing);

				self_config |= srccond->GetInitAttrFlag();
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				effect->FillRep(rep);
				desconstr->FillRep(rep);
				srccond->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix() + ", if itself is " + srccond->DetailAlt3();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + desconstr->DetailAlt1() + effect->Suffix() + ", if itself is " + srccond->DetailAlt3();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy
			{
				srcCondTargetedEff* effect_copy = new srcCondTargetedEff(card_copy,
					(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
					(TargetCond*)(desconstr->CreateNodeHardCopy(card_copy, redir_map)),
					(TargetCond*)(srccond->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}
			GetInitAttrFlag = srccond->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig self_config_copy = self_config; // make a copy for making detailed changes when considering the subtree of the srccond (in particular, whether it is a target on the field or some card target)
				return srccond->GetGlobalSelfConfig(self_config_copy, effect_timing);
			}
			isTargetedAtPlay = overheat_count < overheat_threshold && srccond->CheckThisValid(parent_card);
			CheckPlayValid
			{
				// check for untargetable and stealth attributes
				if (parent_card->owner->IsValidTarget(z))
				{
					Card* card = parent_card->owner->GetTargetCard(z);
					if (card->is_untargetable || (card->is_stealth && parent_card->owner->IsValidCharTarget(z)))
						return false;
				}
				else
					return false;

				return desconstr->CheckPlayValid(x, y, z, parent_card);
			}
			TargetedAction // assuming the destination constraint is valid
			{ 
				if (srccond->CheckThisValid(parent_card) && overheat_count < overheat_threshold) // do not check if the source is dying or something, as deathrattle and on-discard effects still needs be triggered
				{
					overheat_count++;
					parent_card->IncContribution();
					return effect->TargetedAction(z, parent_card, true);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Condition check failed or overheated, not actually activated." << endl;
				#endif
				return false;
			}
		}

	UntargetedEff
	default:
		{
			preselector
			{
				if (effect_timing == EFFECT_TIMING_TURN) // for turn start and turn end effects, it needs to at least specify where the card is (field/hand&/deck), doesn't apply to discard as discard doesn't happen so often as turn start/turn end
					force srcCondUntargetedEff;
				if (!(self_config & TARGET_NOT_LEADER) && effect_timing == EFFECT_TIMING_PLAY) // the source condition on leaders (as characters) at play is not needed as it can be covered by leader condition
					forbid srcCondUntargetedEff;
			}
		}
	:=
	| noCondUntargetedEff: BaseUntargetedEff* effect
		{
			generator
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				switch (effect_timing)
				{
					case EFFECT_TIMING_PLAY:
						if (!(self_config & TARGET_IS_SPELL))
							effect_timing_filter = PLAY_CHAR_SRC_FILTER;
						else if (!(self_config & TARGET_ANY_CHAR))
							effect_timing_filter = PLAY_SPELL_SRC_FILTER;
						break;
					case EFFECT_TIMING_DESTROY:
						effect_timing_filter = DESTROY_SRC_FILTER;
						break;	
				}

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;
				effect = generate BaseUntargetedEff(self_config_copy, effect_timing, effect_depth, give_eff);
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				effect->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy
			{
				noCondUntargetedEff* effect_copy = new noCondUntargetedEff(card_copy, (BaseUntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}
			GetInitAttrFlag = effect->GetInitAttrFlag();
			GetGlobalSelfConfig = effect->GetGlobalSelfConfig(self_config, effect_timing);
			UntargetedAction
			{
				if (overheat_count < overheat_threshold)
				{
					overheat_count++;
					parent_card->IncContribution();
					effect->UntargetedAction(parent_card);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Overheated, not actually activated." << endl;
				#endif
			}
		}
	| indeCondUntargetedEff: BaseUntargetedEff* effect, IndeCond* cond
		{
			generator
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				switch (effect_timing)
				{
					case EFFECT_TIMING_PLAY:
						if (!(self_config & TARGET_IS_SPELL))
							effect_timing_filter = PLAY_CHAR_SRC_FILTER;
						else if (!(self_config & TARGET_ANY_CHAR))
							effect_timing_filter = PLAY_SPELL_SRC_FILTER;
						break;
					case EFFECT_TIMING_DESTROY:
						effect_timing_filter = DESTROY_SRC_FILTER;
						break;
				}

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;
				effect = generate BaseUntargetedEff(self_config_copy, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetLeaderConfig(); // to counter the problem of rvalue assignmed to lvalue 
				cond = generate IndeCond(tmp_init_config, tmp_config, effect_timing);
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
				cond->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + ", if " + cond->Detail();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH: " + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + ", if " + cond->Detail();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy
			{
				indeCondUntargetedEff* effect_copy = new indeCondUntargetedEff(card_copy,
					(BaseUntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
					(IndeCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}
			GetInitAttrFlag = effect->GetInitAttrFlag();
			UntargetedAction
			{ 
				if (cond->CheckThisValid(parent_card) && overheat_count < overheat_threshold)
				{
					overheat_count++;
					parent_card->IncContribution();
					effect->UntargetedAction(parent_card);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Condition check failed or overheated, not actually activated." << endl;	
				#endif			
			}
		}
	| srcCondUntargetedEff: BaseUntargetedEff* effect, TargetCond* srccond
		{
			generator 
			{
				unsigned effect_timing_filter = TARGET_TYPE_ANY;
				switch (effect_timing)
				{
					case EFFECT_TIMING_PLAY:
						if (!(self_config & TARGET_IS_SPELL))
							effect_timing_filter = PLAY_CHAR_SRC_FILTER;
						else if (!(self_config & TARGET_ANY_CHAR))
							effect_timing_filter = PLAY_SPELL_SRC_FILTER;
						break;
					case EFFECT_TIMING_DESTROY:
						effect_timing_filter = DESTROY_SRC_FILTER;
						break;
				}

				CondConfig self_config_copy = self_config;
				self_config_copy &= effect_timing_filter;
				effect = generate BaseUntargetedEff(self_config_copy, effect_timing, effect_depth, give_eff);
				
				CondConfig self_instant_config = effect->GetSelfConfig(self_config);
				self_instant_config &= effect_timing_filter;
				srccond = generate TargetCond(self_config_copy, self_instant_config, TARGET_MODE_SOURCE, effect_timing);

				self_config |= srccond->GetInitAttrFlag();
			}
			overheat_count = 0;
			overheat_threshold = DEFAULT_OVERHEAT_THRESHOLD;
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				effect->FillRep(rep);
				srccond->FillRep(rep);
			}
			Brief = (overheat_count < overheat_threshold ? "" : "(Overheated)");
			Detail
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH:" + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + ", if itself is " + srccond->DetailAlt3();
			}
			DetailIndent
			{
				string overheat_indicator = (overheat_count < overheat_threshold ? "" : "(Overheated)");
				string overheat_counter = (display_overheat_counts ? "(OH:" + IntToStr(overheat_count) + " of " + IntToStr(overheat_threshold) + ")" : "");
				return overheat_indicator + overheat_counter + effect->Detail() + ", if itself is " + srccond->DetailAlt3();
			}
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy 
			{
				srcCondUntargetedEff* effect_copy = new srcCondUntargetedEff(card_copy,
					(BaseUntargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
					(TargetCond*)(srccond->CreateNodeHardCopy(card_copy, redir_map)));

				// make sure to also copy overheat status
				effect_copy->overheat_count = overheat_count;
				effect_copy->overheat_threshold = overheat_threshold;

				return effect_copy;
			}
			GetInitAttrFlag = effect->GetInitAttrFlag() | srccond->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, effect_timing);
				CondConfig self_config_copy = self_config; // make a copy for making detailed changes when considering the subtree of the srccond (in particular, whether it is a target on the field or some card target)
				self_config_copy &= tmp_config;
				tmp_config &= srccond->GetGlobalSelfConfig(self_config_copy, effect_timing);
				return tmp_config;
			}
			UntargetedAction
			{ 
				if (srccond->CheckThisValid(parent_card) && overheat_count < overheat_threshold) // do not check whether the source is dying or something, as deathrattle and on-discard effects still needs be triggered
				{
					overheat_count++;
					parent_card->IncContribution();
					effect->UntargetedAction(parent_card);
				}
				#ifndef SUPPRESS_ALL_MSG
				else
					if (!parent_card->owner->is_exploration)
						cout << "Condition check failed or overheated, not actually activated." << endl;
				#endif
			}
		}

	TargetCond // inside a subtree under TargetCond, all configs are modified in place
	default:
		{
			preselector
			{
				if (!(init_config & TARGET_ANY_CHAR) || !(init_config & TARGET_POS_FIELD)|| !(instant_config & TARGET_ANY_CHAR) || !(instant_config & TARGET_POS_FIELD))
					force cardTargetCond;
				if (!(init_config & TARGET_POS_HAND_OR_DECK) || !(instant_config & TARGET_POS_HAND_OR_DECK)
					|| (target_mode == TARGET_MODE_PLAY && (!(init_config & TARGET_IS_ALLY) || !(instant_config & TARGET_IS_ALLY) // for the target of an targeted effect, if doesn't allow ally, then it has to target at a character
															|| !(init_config & TARGET_POS_HAND) || !(instant_config & TARGET_POS_HAND)))) // for the target of an targeted effect, if doesn't allow hand, then it has to target at a character
					force charTargetCond;
			}
		}
	:=
	| charTargetCond: CharTargetCond* cond
		{
			generator { cond = generate CharTargetCond(init_config, instant_config, target_mode, effect_timing); }
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				cond->FillRep(rep);
			}
			Detail = cond->Detail();
			DetailAlt1 = cond->DetailAlt1();
			DetailAlt2 = cond->DetailAlt2();
			DetailAlt3 = cond->DetailAlt3() + " on the field"; // for source condition
			CreateNodeHardCopy = new charTargetCond(card_copy, (CharTargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = cond->GetInitAttrFlag();
			GetGlobalSelfConfig = cond->GetGlobalSelfConfig(self_config, effect_timing);
			CheckPlayValid = parent_card->owner->IsValidCharTarget(z) && cond->CheckPlayValid(x, y, z, parent_card);
			CheckCardValid = (card->card_pos == CARD_POS_AT_LEADER || card->card_pos == CARD_POS_AT_FIELD) && cond->CheckCardValid(card, parent_card);
			CheckThisValid = (parent_card->card_pos == CARD_POS_AT_LEADER || parent_card->card_pos == CARD_POS_AT_FIELD) && cond->CheckThisValid(parent_card);
		}
	| cardTargetCond: CardTargetCond* cond
		{
			generator { cond = generate CardTargetCond(init_config, instant_config, target_mode, effect_timing); }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				cond->FillRep(rep);
			}
			Detail = cond->Detail();
			DetailAlt1 = cond->DetailAlt1();
			DetailAlt2 = cond->DetailAlt2();
			DetailAlt3 = cond->DetailAlt3(); // for source condition
			CreateNodeHardCopy = new cardTargetCond(card_copy, (CardTargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = cond->GetInitAttrFlag();
			GetGlobalSelfConfig = cond->GetGlobalSelfConfig(self_config, effect_timing);
			CheckPlayValid = parent_card->owner->IsValidCardTarget(z) && cond->CheckPlayValid(x, y, z, parent_card);
			CheckCardValid = (card->card_pos == CARD_POS_AT_HAND || card->card_pos == CARD_POS_AT_DECK) && cond->CheckCardValid(card, parent_card);
			CheckThisValid = (parent_card->card_pos == CARD_POS_AT_HAND || parent_card->card_pos == CARD_POS_AT_DECK) && cond->CheckThisValid(parent_card);
		}

	CharTargetCond :=
	| justCharTargetCond: AllegianceCond* alle, CharTypeCond* typecond, AttrCond* attrcond, StatCond* statcond
		{
			generator
			{
				// this block has to be here (instead in the rules for TargetCond as certain ways of reaching here skip the above rules, e.g. the existence conditions)
				if (target_mode != TARGET_MODE_SOURCE || effect_timing != EFFECT_TIMING_DESTROY)
				{
					// zero or negative HP should only appear on the source of on destroy effect (deathrattle)
					if (init_config.min_hp < 1)
						init_config.min_hp = 1;
					if (instant_config.min_hp < 1)
						instant_config.min_hp = 1;
				}
				if (target_mode == TARGET_MODE_SOURCE && effect_timing == EFFECT_TIMING_PLAY)
				{
					// note that max hp cannot be reduced by effects
					if (instant_config.min_hp < init_config.min_hp)
						instant_config.min_hp = init_config.min_hp;
				}
				if (target_mode == TARGET_MODE_PLAY)
					instant_config &= PLAY_CHAR_TARGET_FILTER;

				if (target_mode == TARGET_MODE_SOURCE && (!(init_config & TARGET_NOT_LEADER) || !(instant_config & TARGET_NOT_LEADER)))
				{
					// source cond on target that must be a leader should only say it is a charactor (as oppose to a card), as other cond should be covered by leader cond; currently applies for turn start/end effects
					alle = construct anyAllegiance();
					typecond = construct isCharacter();
					attrcond = construct noAttrCond();
					statcond = construct noStatCond();
				}
				else
				{
					alle = generate AllegianceCond(init_config, instant_config, target_mode, effect_timing);
					typecond = generate CharTypeCond(init_config, instant_config, target_mode, effect_timing);
					init_config &= typecond->GetTargetConfig(); // choice of earlier part may affect what is available later
					instant_config &= typecond->GetTargetConfig(); // choice of earlier part may affect what is available later
					attrcond = generate AttrCond(init_config, instant_config, target_mode, effect_timing);
					if (!(instant_config & TARGET_POS_HAND_OR_DECK) && target_mode == TARGET_MODE_SOURCE
						&& typecond->isCondTrivial() && attrcond->isCondTrivial()) // do not put trivial condition on source if it is always triggered on the field, e.g. deathrattle (current implementation relies this specific part to resolve it, alle part is always trivial on source mode)
						statcond = generate StatCond(init_config, instant_config, target_mode, effect_timing, true);
					else
						statcond = generate StatCond(init_config, instant_config, target_mode, effect_timing, false);
				}
			}
			FillRep
			{
				// this is just a pass-down node
				alle->FillRep(rep);
				typecond->FillRep(rep);
				attrcond->FillRep(rep);
				statcond->FillRep(rep);
			}
			Detail = alle->Detail() + typecond->Detail() + attrcond->Detail() + statcond->Detail(); // no leading article (for random targetting etc.)
			DetailAlt1 = ((alle->Detail()).length() == 0 ? typecond->DetailAlt1() : alle->DetailAlt1() + typecond->Detail()) + attrcond->Detail() + statcond->Detail();
			DetailAlt2 = alle->Detail() + typecond->DetailAlt2() + attrcond->Detail() + statcond->Detail(); // plural
			DetailAlt3 = typecond->DetailAlt1() + attrcond->Detail() + statcond->Detail(); // source cond always does not need to check for allegiance (any allegiance but in fact is always ally)
			CreateNodeHardCopy = new justCharTargetCond(card_copy,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)),
				(CharTypeCond*)(typecond->CreateNodeHardCopy(card_copy, redir_map)),
				(AttrCond*)(attrcond->CreateNodeHardCopy(card_copy, redir_map)),
				(StatCond*)(statcond->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = attrcond->GetInitAttrFlag();
			GetGlobalSelfConfig
			{ 
				// the alle part doesn't matter as it is only relevant in source cond where there is no need to check for alle (always generated as any alle but effectively always ally)
				// no need to update self_config in the middle as only whether or not it is on field matters
				CondConfig tmp_config = typecond->GetGlobalSelfConfig(self_config, effect_timing);
				tmp_config &= attrcond->GetGlobalSelfConfig(self_config, effect_timing);
				tmp_config &= statcond->GetGlobalSelfConfig(self_config, effect_timing);
				return tmp_config;
			}
			CheckPlayValid = alle->CheckPlayValid(x, y, z, parent_card) && typecond->CheckPlayValid(x, y, z, parent_card) && attrcond->CheckPlayValid(x, y, z, parent_card) && statcond->CheckPlayValid(x, y, z, parent_card);
			CheckCardValid = alle->CheckCardValid(card, parent_card) && typecond->CheckCardValid(card, parent_card) && attrcond->CheckCardValid(card, parent_card) && statcond->CheckCardValid(card, parent_card);
			CheckThisValid = alle->CheckThisValid(parent_card) && typecond->CheckThisValid(parent_card) && attrcond->CheckThisValid(parent_card) && statcond->CheckThisValid(parent_card);
		}

	CharTypeCond
	default:
		{
			preselector
			{
				// note that the card type doesn't change (while minion type can)
				// if it isn't a minion (so it is a leader) then isCharacter is the only choice
				if (!(init_config & TARGET_IS_MINION) || !(instant_config & TARGET_IS_MINION))
					force isCharacter;

				//  if the condition doesn't allow leaders, we don't want to include leader as a possibility (well we could always say a charactor for source condition but it would sound better to say a minion, or a beast minion etc.)
				if (!(init_config & TARGET_IS_LEADER) || !(instant_config & TARGET_IS_LEADER))
					forbid isCharacter;

				// note forbidding a minion type meaning not specifically conditioned on that type, but the effect may still be applicable for that type
				// also, we don't want the minion condition to be too trivial (initially true)
				if (!(init_config & TARGET_NOT_BEAST) || !(instant_config & TARGET_IS_BEAST))
					forbid isBeast;
				if (!(init_config & TARGET_NOT_DRAGON) || !(instant_config & TARGET_IS_DRAGON))
					forbid isDragon;
				if (!(init_config & TARGET_NOT_DEMON) || !(instant_config & TARGET_IS_DEMON))
					forbid isDemon;
			}
		}
	:=
	| isCharacter:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			Detail = "character";
			DetailAlt1 = "a character";
			DetailAlt2 = "characters";
			CreateNodeHardCopy = new isCharacter(card_copy);
			GetTargetConfig
			{
				CondConfig tmp_config = CHAR_COND_FILTER; // this will call the constructor (so no need to explicitly call GetFlagConfig here), similar for cases later
				tmp_config.max_hp = 10; // make this to be also limited to 10, for convenience of the config system for nested effects (otherwise it may try to give minions HP conditions that is larger than 10, which would be very hard to resolve)
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
		}
	| isMinion:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			isCondTrivial = true; // card type cannot change, so for our purpose, this is also considered trivial
			Detail = "minion";
			DetailAlt1 = "a minion";
			DetailAlt2 = "minions";
			CreateNodeHardCopy = new isMinion(card_copy);
			GetTargetConfig
			{
				CondConfig tmp_config =	MINION_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->IsValidMinionTarget(z);
			CheckCardValid = card->card_type == MINION_CARD;
			CheckThisValid = parent_card->card_type == MINION_CARD;
		}
	| isBeast:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			Detail = "Beast";
			DetailAlt1 = "a Beast";
			DetailAlt2 = "Beasts";
			CreateNodeHardCopy = new isBeast(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = NOT_BEAST_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	BEAST_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->IsValidMinionTarget(z) && parent_card->owner->GetTargetCard(z)->minion_type == BEAST_MINION;
			CheckCardValid = card->minion_type == BEAST_MINION;
			CheckThisValid = parent_card->minion_type == BEAST_MINION;
		}
	| isDragon:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(3));
			}
			Detail = "Dragon";
			DetailAlt1 = "a Dragon";
			DetailAlt2 = "Dragons";
			CreateNodeHardCopy = new isDragon(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = NOT_DRAGON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	DRAGON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->IsValidMinionTarget(z) && parent_card->owner->GetTargetCard(z)->minion_type == DRAGON_MINION;
			CheckCardValid = card->minion_type == DRAGON_MINION;
			CheckThisValid = parent_card->minion_type == DRAGON_MINION;
		}
	| isDemon:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(4));
			}	
			Detail = "Demon";
			DetailAlt1 = "a Demon";
			DetailAlt2 = "Demons";
			CreateNodeHardCopy = new isDemon(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = NOT_DEMON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	DEMON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->IsValidMinionTarget(z) && parent_card->owner->GetTargetCard(z)->minion_type == DEMON_MINION;
			CheckCardValid = card->minion_type == DEMON_MINION;
			CheckThisValid = parent_card->minion_type == DEMON_MINION;
		}

	CardTargetCond :=
	| justCardTargetCond: CardPosCond* pos, AllegianceCond* alle, CardTypeCond* typecond, AttrCond* attrcond, StatCond* statcond
		{
			generator
			{
				// this block has to be here (instead in the rules for TargetCond as certain ways of reaching here skip the above rules, e.g. the existence conditions)
				// zero or negative HP should only appear on the source of on destroy effect (deathrattle), never happen to card target
				if (init_config.min_hp < 1)
					init_config.min_hp = 1;
				if (instant_config.min_hp < 1)
					instant_config.min_hp = 1;
				// note that max hp cannot be reduced by effects
				if (instant_config.min_hp < init_config.min_hp)
					instant_config.min_hp = init_config.min_hp;
				if (target_mode == TARGET_MODE_PLAY)
					instant_config &= PLAY_CARD_TARGET_FILTER;

				pos = generate CardPosCond(init_config, instant_config, target_mode, effect_timing); // it is important not to update config with this part (or at least should not remove the bit on TARGET_POS_FIELD), as it is used for the trivialibility mechanism below
				alle = generate AllegianceCond(init_config, instant_config, target_mode, effect_timing);
				typecond = generate CardTypeCond(init_config, instant_config, target_mode, effect_timing);
				init_config &= typecond->GetTargetConfig(); // choice of earlier part may affect what is available later
				instant_config &= typecond->GetTargetConfig(); // choice of earlier part may affect what is available later
				attrcond = generate AttrCond(init_config, instant_config, target_mode, effect_timing);
				if (!(instant_config & TARGET_POS_FIELD) && target_mode == TARGET_MODE_SOURCE
					&& pos->isCondTrivial() && typecond->isCondTrivial() && attrcond->isCondTrivial()) // do not put trivial condition on source (current implementation relies this specific part to resolve it, alle part is always trivial on source mode)
					statcond = generate StatCond(init_config, instant_config, target_mode, true, effect_timing);
				else
					statcond = generate StatCond(init_config, instant_config, target_mode, false, effect_timing);
			}
			FillRep
			{
				// this is just a pass-down node
				pos->FillRep(rep);
				alle->FillRep(rep);
				typecond->FillRep(rep);
				attrcond->FillRep(rep);
				statcond->FillRep(rep);
			}
			Detail = typecond->Detail() + attrcond->Detail() + statcond->Detail() + " at " + alle->DetailAlt3() + pos->Detail(); // no leading article (for random targetting etc.)
			DetailAlt1 = typecond->DetailAlt1() + attrcond->Detail() + statcond->Detail() + " at " + alle->DetailAlt2() + pos->Detail();
			DetailAlt2 = typecond->DetailAlt2() + attrcond->Detail() + statcond->Detail() + " at " + alle->DetailAlt2() + ((alle->Detail()).length() == 0 ? pos->DetailAlt2() : pos->DetailAlt1()); // plural
			DetailAlt3 = typecond->DetailAlt1() + attrcond->Detail() + statcond->Detail() + " at " + pos->Detail(); // source cond always does not need to check for allegiance (any allegiance but in fact is always ally)
			CreateNodeHardCopy = new justCardTargetCond(card_copy,
				(CardPosCond*)(pos->CreateNodeHardCopy(card_copy, redir_map)),
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)),
				(CardTypeCond*)(typecond->CreateNodeHardCopy(card_copy, redir_map)),
				(AttrCond*)(attrcond->CreateNodeHardCopy(card_copy, redir_map)),
				(StatCond*)(statcond->CreateNodeHardCopy(card_copy, redir_map)));
			GetInitAttrFlag = attrcond->GetInitAttrFlag();
			GetGlobalSelfConfig
			{
				// the pos part doesn't matter as pos isn't giving any globally meaningful constraints 
				// the alle part doesn't matter as it is only relevant in source cond where there is no need to check for alle (always generated as any alle but effectively always ally)
				// no need to update self_config in the middle as only whether or not it is on field matters
				CondConfig tmp_config = typecond->GetGlobalSelfConfig(self_config, effect_timing);
				tmp_config &= attrcond->GetGlobalSelfConfig(self_config, effect_timing);
				tmp_config &= statcond->GetGlobalSelfConfig(self_config, effect_timing);
				return tmp_config;
			}
			CheckPlayValid = pos->CheckPlayValid(x, y, z, parent_card) && alle->CheckPlayValid(x, y, z, parent_card) && typecond->CheckPlayValid(x, y, z, parent_card) && attrcond->CheckPlayValid(x, y, z, parent_card) && statcond->CheckPlayValid(x, y, z, parent_card);
			CheckCardValid = pos->CheckCardValid(card, parent_card) && alle->CheckCardValid(card, parent_card) && typecond->CheckCardValid(card, parent_card) && attrcond->CheckCardValid(card, parent_card) && statcond->CheckCardValid(card, parent_card);
			CheckThisValid = pos->CheckThisValid(parent_card) && alle->CheckThisValid(parent_card) && typecond->CheckThisValid(parent_card) && attrcond->CheckThisValid(parent_card) && statcond->CheckThisValid(parent_card);
		}

	CardTypeCond
	default:
		{
			preselector
			{
				// note that card type doesn't change (while minion type can)
				// so don't just require on card type if it is source condition (somewhat different from the CardTypeCond mechanism just because there minion sounds better to say than character when it applies)
				if (target_mode == TARGET_MODE_SOURCE)
				{
					forbid isLeaderCard, isMinionCard, isSpellCard;
					if (!(init_config & TARGET_IS_MINION) || !(instant_config & TARGET_IS_MINION))
						force isCard; // as all the detailed minion types are also forbidden in this case
				}
				else
				{
					// forbid card type if it is not allowed, also forbidding types that contains the type (isCard), as this is not the case of source condition
					if (!(init_config & TARGET_IS_LEADER) || !(instant_config & TARGET_IS_LEADER))
						forbid isCard, isLeaderCard;
					if (!(init_config & TARGET_IS_MINION) || !(instant_config & TARGET_IS_MINION))
						forbid isCard, isMinionCard, isBeastCard, isDragonCard, isDemonCard;
					if (!(init_config & TARGET_IS_SPELL) || !(instant_config & TARGET_IS_SPELL))
						forbid isCard, isSpellCard;
				}

				// note forbidding a minion type meaning not specifically conditioned on that type, but the effect may still be applicable for that type
				// also, we don't want the minion condition to be too trivial (initially true)
				if (!(init_config & TARGET_NOT_BEAST) || !(instant_config & TARGET_IS_BEAST))
					forbid isBeastCard;
				if (!(init_config & TARGET_NOT_DRAGON) || !(instant_config & TARGET_IS_DRAGON))
					forbid isDragonCard;
				if (!(init_config & TARGET_NOT_DEMON) || !(instant_config & TARGET_IS_DEMON))
					forbid isDemonCard;
			}
		}
	:=
	| isCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			Detail = "card";
			DetailAlt1 = "a card";
			DetailAlt2 = "cards";
			CreateNodeHardCopy = new isCard(card_copy);
			GetTargetConfig
			{
				CondConfig tmp_config =	TARGET_TYPE_ANY;
				tmp_config.max_hp = 10; // make this to be also limited to 10, for convenience of the config system for nested effects (otherwise it may try to give minions HP conditions that is larger than 10, which would be very hard to resolve)
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
		}
	| isLeaderCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			isCondTrivial = true; // card type cannot change, so for our purpose, this is also considered trivial
			Detail = "leader card";
			DetailAlt1 = "a leader card";
			DetailAlt2 = "leader cards";
			CreateNodeHardCopy = new isLeaderCard(card_copy);
			GetTargetConfig = LEADER_COND_FILTER;
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->card_type == LEADER_CARD;
			CheckCardValid = card->card_type == LEADER_CARD;
			CheckThisValid = parent_card->card_type == LEADER_CARD;
		}
	| isMinionCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			isCondTrivial = true; // card type cannot change, so for our purpose, this is also considered trivial
			Detail = "minion card";
			DetailAlt1 = "a minion card";
			DetailAlt2 = "minion cards";
			CreateNodeHardCopy = new isMinionCard(card_copy);
			GetTargetConfig
			{
				CondConfig tmp_config =	MINION_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->card_type == MINION_CARD;
			CheckCardValid = card->card_type == MINION_CARD;
			CheckThisValid = parent_card->card_type == MINION_CARD;
		}
	| isSpellCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(3));
			}
			isCondTrivial = true;
			Detail = "spell card";
			DetailAlt1 = "a spell card";
			DetailAlt2 = "spell cards";
			CreateNodeHardCopy = new isSpellCard(card_copy);
			GetTargetConfig = SPELL_COND_FILTER;
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->card_type == SPELL_CARD;
			CheckCardValid = card->card_type == SPELL_CARD;
			CheckThisValid = parent_card->card_type == SPELL_CARD;
		}
	| isBeastCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(4));
			}
			Detail = "Beast card";
			DetailAlt1 = "a Beast card";
			DetailAlt2 = "Beast cards";
			CreateNodeHardCopy = new isBeastCard(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config =	NOT_BEAST_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	BEAST_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->minion_type == BEAST_MINION;
			CheckCardValid = card->minion_type == BEAST_MINION;
			CheckThisValid = parent_card->minion_type == BEAST_MINION;
		}
	| isDragonCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(5));
			}
			Detail = "Dragon card";
			DetailAlt1 = "a Dragon card";
			DetailAlt2 = "Dragon cards";
			CreateNodeHardCopy = new isDragonCard(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config =	NOT_DRAGON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	DRAGON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->minion_type == DRAGON_MINION;
			CheckCardValid = card->minion_type == DRAGON_MINION;
			CheckThisValid = parent_card->minion_type == DRAGON_MINION;
		}
	| isDemonCard:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(6));
			}
			Detail = "Demon card";
			DetailAlt1 = "a Demon card";
			DetailAlt2 = "Demon cards";
			CreateNodeHardCopy = new isDemonCard(card_copy);
			GetGlobalSelfConfig
			{
				CondConfig tmp_config =	NOT_DEMON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			GetTargetConfig
			{
				CondConfig tmp_config =	DEMON_COND_FILTER;
				tmp_config.max_hp = 10;
				if (tmp_config.min_hp > 10)
					tmp_config.min_hp = 10;
				return tmp_config;
			}
			CheckPlayValid = parent_card->owner->GetTargetCard(z)->minion_type == DEMON_MINION;
			CheckCardValid = card->minion_type == DEMON_MINION;
			CheckThisValid = parent_card->minion_type == DEMON_MINION;
		}

	CardPosCond
	default:
		{
			preselector
			{
				if (!(instant_config & TARGET_POS_DECK))
					force cardPosAtHand;
				if (!(instant_config & TARGET_POS_HAND))
					force cardPosAtDeck;
			}
		}
	:=	// note that only cards in ones own hand is targetable at play, which is already deal with by the IsValidCardTarget function for the higher up rules, therefore no need to be considered here
	| cardPosAtHandOrDeck:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			Detail = "hand or deck";
			DetailAlt1 = "hand and deck";
			DetailAlt2 = "hands and decks";
			CreateNodeHardCopy = new cardPosAtHandOrDeck(card_copy);
		}
	| cardPosAtHand:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			Detail = "hand";
			DetailAlt2 = "hands";
			CreateNodeHardCopy = new cardPosAtHand(card_copy);
			CheckCardValid = card->card_pos == CARD_POS_AT_HAND;
			CheckThisValid = parent_card->card_pos == CARD_POS_AT_HAND;
		}
	| cardPosAtDeck:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			Detail = "deck";
			DetailAlt2 = "decks";
			CreateNodeHardCopy = new cardPosAtDeck(card_copy);
			CheckCardValid = card->card_pos == CARD_POS_AT_DECK;
			CheckThisValid = parent_card->card_pos == CARD_POS_AT_DECK;
		}

	AllegianceCond
	default:
		{
			preselector
			{
				if (target_mode == TARGET_MODE_SOURCE) // for conditions on source it is forced anyAllegiance, as it is always ally, doesn't make sense to put any condition
					force anyAllegiance;
				if (target_mode == TARGET_MODE_MOVE_DEST || target_mode == TARGET_MODE_WIN_GAME) // for move destination, it can only be either ally or opponent, but not both; for win game we think an effect intensionally result in a draw is boring
					forbid anyAllegiance;
				if (!(instant_config & TARGET_IS_OPPO))
					force allyAllegiance;
				if (!(instant_config & TARGET_IS_ALLY))
					force oppoAllegiance;
			}
		}
	:=
	| anyAllegiance:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			DetailAlt2 = "both players\' "; // for aoe, etc.
			DetailAlt3 = "either player\'s "; // for random
			DetailAlt4 = "both leaders"; // for leader untargeted effects
			DetailAlt5 = "Both players "; // for targets with the player as subject
			DetailAlt6 = "both players"; // a variant to above, not at the start of a sentence
			IsPlural = true;
			CreateNodeHardCopy = new anyAllegiance(card_copy);
		}
	| allyAllegiance:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			Detail = "friendly ";
			DetailAlt1 = "a friendly ";
			DetailAlt2 = "your ";
			DetailAlt3 = "your ";
			DetailAlt4 = "your leader"; // for leader untargeted effects
			DetailAlt5 = "You "; // for targets with the player as subject
			DetailAlt6 = "you"; // a variant to above, not at the start of a sentence
			CreateNodeHardCopy = new allyAllegiance(card_copy);
			GetTargetConfig = ALLY_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsTargetAlly(z);
			CheckCardValid = card->owner == parent_card->owner;
		}
	| oppoAllegiance:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			Detail = "enemy ";
			DetailAlt1 = "an enemy ";
			DetailAlt2 = "the opponent\'s ";
			DetailAlt3 = "the opponent\'s ";
			DetailAlt4 = "the opponent\'s leader"; // for leader untargeted effects
			DetailAlt5 = "Your opponent "; // for targets with the player as subject
			DetailAlt6 = "your opponent"; // a variant to above, not at the start of a sentence
			IsThirdPersonSingle = true;
			CreateNodeHardCopy = new oppoAllegiance(card_copy);
			GetTargetConfig = OPPO_COND_FILTER;
			CheckThisValid = false;
			CheckPlayValid = parent_card->owner->IsTargetOpponent(z);
			CheckCardValid = card->owner == parent_card->opponent;
		}

	AttrCond
	default:
		{
			preselector
			{

				// we don't want the attribute condition to be too trivial (initially true)
				// stealth and shield attributes are treated a little bit differently as they are easily lost
				if ((init_config & TARGET_IS_CHARGE) || !(instant_config & TARGET_IS_CHARGE) || (init_config & TARGET_IS_SPELL))
					forbid chargeCond;
				if ((init_config & TARGET_IS_TAUNT) || !(instant_config & TARGET_IS_TAUNT) || (init_config & TARGET_IS_SPELL))
					forbid tauntCond;
				if (((init_config & TARGET_IS_STEALTH) && (!(instant_config & TARGET_POS_FIELD) || (target_mode == TARGET_MODE_SOURCE && effect_timing == EFFECT_TIMING_PLAY))) || !(instant_config & TARGET_IS_STEALTH) || (init_config & (TARGET_IS_SPELL | TARGET_IS_LEADER)))
					forbid stealthCond;
				if ((init_config & TARGET_IS_UNTARGETABLE) || !(instant_config & TARGET_IS_UNTARGETABLE))
					forbid untargetableCond;
				if (((init_config & TARGET_IS_SHIELDED) && (!(instant_config & TARGET_POS_FIELD) || (target_mode == TARGET_MODE_SOURCE && effect_timing == EFFECT_TIMING_PLAY))) || !(instant_config & TARGET_IS_SHIELDED) || (init_config & TARGET_IS_SPELL))
					forbid shieldCond;
				if ((init_config & TARGET_IS_POISONOUS) || !(instant_config & TARGET_IS_POISONOUS))
					forbid poisonousCond;
				if ((init_config & TARGET_IS_LIFESTEAL) || !(instant_config & TARGET_IS_LIFESTEAL))
					forbid lifestealCond;
			}
		}
	:=
	| noAttrCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			CreateNodeHardCopy = new noAttrCond(card_copy);
		}
	| chargeCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			Detail = " with Charge";
			CreateNodeHardCopy = new chargeCond(card_copy);
			GetInitAttrFlag = TARGET_IS_CHARGE;
			GetGlobalSelfConfig = NOT_CHARGE_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_charge;
			CheckCardValid = card->is_charge;
			CheckThisValid = parent_card->is_charge;
		}
	| tauntCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(2));
			}
			Detail = " with Taunt";
			CreateNodeHardCopy = new tauntCond(card_copy);
			GetInitAttrFlag = TARGET_IS_TAUNT;
			GetGlobalSelfConfig = NOT_TAUNT_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_taunt;
			CheckCardValid = card->is_taunt;
			CheckThisValid = parent_card->is_taunt;
		}
	| stealthCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(3));
			}
			Detail = " with Stealth";
			CreateNodeHardCopy = new stealthCond(card_copy);
			GetInitAttrFlag = TARGET_IS_STEALTH;
			GetGlobalSelfConfig = ((!(self_config & TARGET_POS_FIELD) || effect_timing == EFFECT_TIMING_PLAY) ? NOT_STEALTH_COND_FILTER : TARGET_TYPE_ANY); // special as stealth is easily lost when staying on the field
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_stealth;
			CheckCardValid = card->is_stealth;
			CheckThisValid = parent_card->is_stealth;
		}
	| untargetableCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(4));
			}
			Detail = " with Untargetability";
			CreateNodeHardCopy = new untargetableCond(card_copy);
			GetInitAttrFlag = TARGET_IS_UNTARGETABLE;
			GetGlobalSelfConfig = NOT_UNTARGETABLE_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_untargetable;
			CheckCardValid = card->is_untargetable;
			CheckThisValid = parent_card->is_untargetable;
		}
	| shieldCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(5));
			}
			Detail = " with Shield";
			CreateNodeHardCopy = new shieldCond(card_copy);
			GetInitAttrFlag = TARGET_IS_SHIELDED;
			GetGlobalSelfConfig = ((!(self_config & TARGET_POS_FIELD) || effect_timing == EFFECT_TIMING_PLAY) ? NOT_SHIELDED_COND_FILTER : TARGET_TYPE_ANY); // special as stealth is easily lost when staying on the field
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_shielded;
			CheckCardValid = card->is_shielded;
			CheckThisValid = parent_card->is_shielded;
		}
	| poisonousCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(6));
			}
			Detail = " with Poison";
			CreateNodeHardCopy = new poisonousCond(card_copy);
			GetInitAttrFlag = TARGET_IS_POISONOUS;
			GetGlobalSelfConfig = NOT_POISONOUS_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_poisonous;
			CheckCardValid = card->is_poisonous;
			CheckThisValid = parent_card->is_poisonous;
		}
	| lifestealCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(7));
			}
			Detail = " with Lifesteal";
			CreateNodeHardCopy = new lifestealCond(card_copy);
			GetInitAttrFlag = TARGET_IS_LIFESTEAL;
			GetGlobalSelfConfig = NOT_LIFESTEAL_COND_FILTER;
			CheckPlayValid = parent_card->owner->IsValidTarget(z) && parent_card->owner->GetTargetCard(z)->is_lifesteal;
			CheckCardValid = card->is_lifesteal;
			CheckThisValid = parent_card->is_lifesteal;
		}

	StatCond
	default:
		{
			preselector
			{
				if ((init_config & TARGET_IS_SPELL) || !(instant_config & TARGET_ANY_CHAR) || ((instant_config & TARGET_IS_SPELL) && target_mode != TARGET_MODE_SOURCE)) // spells only has cost stat; also for source condition it wouldn't say isSpellCard (it says isCard instead, so the check would be special)
					forbid atkCond, hpCond, atkTimesCond;

				// scale each type of condition with nontrival ranges (the range for lower bound requirement + the range for upper bound requirement), assuming when foring nontrival one of this has to have none zero weights
				// note that the default clamping off of negative probs are done before these so we need to check if the scales are negative here manually
				int cost_scale = init_config.max_cost - init_config.min_cost + instant_config.max_cost - instant_config.min_cost;
				probof(costCond) *= (cost_scale > 0 ? 0.1 * cost_scale : 0); // the 0.1 is to balance with noStatCond
				int atk_scale = init_config.max_atk - init_config.min_atk + instant_config.max_atk - instant_config.min_atk;
				probof(atkCond) *= (atk_scale > 0 ? 0.1 * atk_scale : 0);
				int hp_scale = init_config.max_hp - init_config.min_hp + instant_config.max_hp - instant_config.min_hp;
				probof(hpCond) *= (hp_scale > 0 ? 0.1 * hp_scale : 0);
				int n_atks_scale = init_config.max_n_atks - init_config.min_n_atks + instant_config.max_n_atks - instant_config.min_n_atks;
				probof(atkTimesCond) *= (n_atks_scale > 0 ? 0.1 * n_atks_scale : 0);

				if (force_nontrivial && (probof(costCond) > 0 || probof(atkCond) > 0 || probof(hpCond) > 0 || probof(atkTimesCond) > 0))
					forbid noStatCond;
			}
		}
	:=
	| noStatCond:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(0));
			}
			isCondTrivial = true;
			CreateNodeHardCopy = new noStatCond(card_copy);
		}
	| costCond: StatCondVariant* variant
		{
			generator 
			{
				int lower_min = init_config.min_cost + 1;
				int lower_max = instant_config.max_cost;
				int upper_min = instant_config.min_cost;
				int upper_max = init_config.max_cost - 1;
				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				variant->FillRep(rep);
			}
			Detail = " having" + variant->Detail() + " mana cost";
			CreateNodeHardCopy = new costCond(card_copy, (StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				int min_val = self_config.min_cost;
				int max_val = self_config.max_cost;
				variant->AdjustGlobalStatRange(min_val, max_val);
				return GetCostConfig(TARGET_TYPE_ANY, min_val, max_val);
			}
			CheckPlayValid = variant->CheckStatValid(parent_card->owner->GetTargetCard(z)->mana);
			CheckCardValid = variant->CheckStatValid(card->mana);
			CheckThisValid = variant->CheckStatValid(parent_card->mana);
		}
	| atkCond: StatCondVariant* variant
		{
			generator 
			{
				int lower_min = init_config.min_atk + 1;
				int lower_max = instant_config.max_atk;
				int upper_min = instant_config.min_atk;
				int upper_max = init_config.max_atk - 1;
				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				variant->FillRep(rep);
			}
			Detail = " having" + variant->Detail() + " attack";
			CreateNodeHardCopy = new atkCond(card_copy, (StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				int min_val = self_config.min_atk;
				int max_val = self_config.max_atk;
				variant->AdjustGlobalStatRange(min_val, max_val);
				return GetAtkConfig(CHAR_COND_FILTER, min_val, max_val);
			}
			CheckPlayValid = variant->CheckStatValid(parent_card->owner->GetTargetCard(z)->atk);
			CheckCardValid = variant->CheckStatValid(card->atk);
			CheckThisValid = variant->CheckStatValid(parent_card->atk);
		}
	| hpCond: StatCondVariant* variant
		{
			generator
			{
				int lower_min = init_config.min_hp + 1;
				int lower_max = instant_config.max_hp;
				int upper_min = instant_config.min_hp;
				int upper_max = init_config.max_hp - 1;
				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(3));
				variant->FillRep(rep);
			}
			Detail = " having" + variant->Detail() + " health";
			CreateNodeHardCopy = new hpCond(card_copy, (StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				int min_val = self_config.min_hp;
				int max_val = self_config.max_hp;
				variant->AdjustGlobalStatRange(min_val, max_val);
				return GetHpConfig(CHAR_COND_FILTER, min_val, max_val);
			}
			CheckPlayValid { Card* card = parent_card->owner->GetTargetCard(z); return variant->CheckStatValid(card->max_hp - card->hp_loss); }
			CheckCardValid = variant->CheckStatValid(card->max_hp - card->hp_loss);
			CheckThisValid = variant->CheckStatValid(parent_card->max_hp - parent_card->hp_loss);
		}
	| atkTimesCond: StatCondVariant* variant
		{
			generator
			{
				int lower_min = init_config.min_n_atks + 1;
				int lower_max = instant_config.max_n_atks;
				int upper_min = instant_config.min_n_atks;
				int upper_max = init_config.max_n_atks - 1;
				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4));
				variant->FillRep(rep);
			}
			Detail = " having" + variant->Detail() + (variant->IsPlural() ? " attack times" : " attack time");
			CreateNodeHardCopy = new atkTimesCond(card_copy, (StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				int min_val = self_config.min_n_atks;
				int max_val = self_config.max_n_atks;
				variant->AdjustGlobalStatRange(min_val, max_val);
				return GetAtkTimesConfig(CHAR_COND_FILTER, min_val, max_val);
			}
			CheckPlayValid { Card* card = parent_card->owner->GetTargetCard(z); return variant->CheckStatValid(card->max_n_atks - card->n_atks_loss); }
			CheckCardValid = variant->CheckStatValid(card->max_n_atks - card->n_atks_loss);
			CheckThisValid = variant->CheckStatValid(parent_card->max_n_atks - parent_card->n_atks_loss);
		}

	StatCondVariant
	default:
		{
			preselector
			{
				// scale the weights for "at least" and "at most" with the reasonable range
				probof(statGe) *= lower_max - lower_min + 1;
				probof(statLe) *= upper_max - upper_min + 1;
			}
		}
	:=
	| statGe: int val
		{
			generator { val = GetRandInt(lower_min, lower_max); }
			FillRep
			{
				rep.push_back(mkNodeRep(0, <double>{NormalizeCode(val, 0, 10)})); // well the val can be outside this range but it will be in for most of the time
			}
			Detail = " at least " + IntToStr(val);
			IsPlural = (val != 1 && val != -1);
			CreateNodeHardCopy = new statGe(card_copy, val);
			AdjustGlobalStatRange { if (max_val >= val) max_val = val - 1; }
			CheckStatValid = stat_val >= val;
		}
	| statLe: int val
		{
			generator { val = GetRandInt(upper_min, upper_max); }
			FillRep
			{
				rep.push_back(mkNodeRep(1, <double>{NormalizeCode(val, 0, 10)})); // well the val can be outside this range but it will be in for most of the time
			}
			Detail = " at most " + IntToStr(val);
			IsPlural = (val != 1 && val != -1);
			CreateNodeHardCopy = new statLe(card_copy, val);
			AdjustGlobalStatRange { if (min_val <= val) min_val = val + 1; }
			CheckStatValid = stat_val <= val;
		}

	IndeCond
	default:
		{
			preselector
			{
				if (effect_timing == EFFECT_TIMING_PLAY) // as playing a card generally consumes MP, having mpCond on play effect has some nasty ambiguity, we just forbid this from happening
					forbid mpCond;
			}
		}
	:=
	| fieldExistenceCond: CharTargetCond* cond
		{
			generator 
			{ 
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = TARGET_POS_FIELD | TARGET_IS_MINION | TARGET_ANY_ALLE_MINION_ATTR_TYPE; // to counter the problem of rvalue passed to lvalue ref
				cond = generate CharTargetCond(tmp_init_config, tmp_config, TARGET_MODE_EXIST, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				cond->FillRep(rep);
			}
			Detail = "there is " + cond->DetailAlt1() + " on the field (not considering this card)";
			CreateNodeHardCopy = new fieldExistenceCond(card_copy, (CharTargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			CheckThisValid
			{
				for (int i = 0; i < parent_card->owner->field.size(); i++)
				{
					Card* target = parent_card->owner->field[i];
					if (target && target != parent_card && !target->is_dying && cond->CheckCardValid(target, parent_card))
						return true;
				}
				for (int i = 0; i < parent_card->opponent->field.size(); i++)
				{
					Card* target = parent_card->opponent->field[i];
					if (target && target != parent_card && !target->is_dying && cond->CheckCardValid(target, parent_card))
						return true;
				}
				return false;
			}
		}
	| cardExistenceCond: CardTargetCond* cond
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = TARGET_POS_HAND_OR_DECK | TARGET_IS_ALLY | TARGET_ANY_CARD_MINION_ATTR_TYPE; // to counter the problem of rvalue passed to lvalue ref
				cond = generate CardTargetCond(tmp_init_config, tmp_config, TARGET_MODE_EXIST, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				cond->FillRep(rep);
			}
			Detail = "there is " + cond->DetailAlt1() + " (not considering this card)";
			CreateNodeHardCopy = new cardExistenceCond(card_copy, (CardTargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			CheckThisValid
			{
				for (int i = 0; i < parent_card->owner->hand.size(); i++)
				{
					Card* target = parent_card->owner->hand[i];
					if (target && target != parent_card && !target->is_dying && cond->CheckCardValid(target, parent_card))
						return true;
				}
				for (int i = 0; i < parent_card->owner->deck.size(); i++)
				{
					Card* target = parent_card->owner->deck[i];
					if (target && target != parent_card && !target->is_dying && cond->CheckCardValid(target, parent_card))
						return true;
				}
				return false;
			}
		}
	| leaderCond: AllegianceCond* alle, AttrCond* attrcond, StatCond* statcond
		{
			generator
			{
				CondConfig init_config = TARGET_POS_FIELD | TARGET_IS_LEADER | TARGET_ANY_ALLE_TYPE;
				init_config.min_hp = 1; // condition on leaders should always ask for positive hp		
				CondConfig instant_config = LEADER_COND_FILTER & FIELD_COND_FILTER;
				instant_config.min_hp = 1; // condition on leaders should always ask for positive hp
				alle = generate AllegianceCond(init_config, instant_config, TARGET_MODE_LEADER, effect_timing);
				// only apply the leader config if the allegiance setting in the config is covered by the allegiance setting here
				if (!(instant_leader_config.flag & ~alle->GetTargetConfig().flag))
					instant_config &= instant_leader_config;
				attrcond = generate AttrCond(init_config, instant_config, TARGET_MODE_LEADER, effect_timing);
				if (attrcond->isCondTrivial())
					statcond = generate StatCond(init_config, instant_config, TARGET_MODE_LEADER, effect_timing, true);
				else
					statcond = generate StatCond(init_config, instant_config, TARGET_MODE_LEADER, effect_timing, false);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				alle->FillRep(rep);
				attrcond->FillRep(rep);
				statcond->FillRep(rep);
			}
			Detail = alle->DetailAlt4() + (alle->IsPlural() ? " are" : " is") + attrcond->Detail() + statcond->Detail();
			CreateNodeHardCopy = new leaderCond(card_copy,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)),
				(AttrCond*)(attrcond->CreateNodeHardCopy(card_copy, redir_map)),
				(StatCond*)(statcond->CreateNodeHardCopy(card_copy, redir_map)));
			CheckThisValid
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					if (!(attrcond->CheckCardValid(target_a, parent_card) && statcond->CheckCardValid(target_a, parent_card)))
						return false;
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					if (!(attrcond->CheckCardValid(target_b, parent_card) && statcond->CheckCardValid(target_b, parent_card)))
						return false;
				return true;
			}
		}
	| mpCond: AllegianceCond* alle, StatCondVariant* variant
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);

				// we are using the configure that is used for leader also for mp and max mp as currently they can't be both modified in the same effect.
				int instant_min_mp = 0, instant_max_mp = 10;
				// only apply the leader config if the allegiance setting in the config is covered by the allegiance setting here
				if (!(instant_leader_config.flag & ~alle->GetTargetConfig().flag))
				{
					instant_min_mp = instant_leader_config.min_mp;
					instant_max_mp = instant_leader_config.max_mp;
				}
			
				// note that the "init_config" here is not passed in as a parameter as it is always default
				int lower_min = 1;
				int lower_max = instant_max_mp;
				int upper_min = instant_min_mp;
				int upper_max = 9;

				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(3));
				alle->FillRep(rep);
				variant->FillRep(rep);
			}
			Detail = alle->DetailAlt6() + (alle->IsThirdPersonSingle() ?  " has" : " have") + variant->Detail() + " MP";
			CreateNodeHardCopy = new mpCond(card_copy,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)),
				(StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			CheckThisValid
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					if (!variant->CheckStatValid(parent_card->owner->max_mp - parent_card->owner->mp_loss))
						return false;
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					if (!variant->CheckStatValid(parent_card->opponent->max_mp - parent_card->opponent->mp_loss))
						return false;
				return true;
			}
		}
	| maxMpCond: AllegianceCond* alle, StatCondVariant* variant
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);

				// we are using the configure that is used for leader also for mp and max mp as currently they can't be both modified in the same effect.
				int instant_min_max_mp = 0, instant_max_max_mp = 10;
				// only apply the leader config if the allegiance setting in the config is covered by the allegiance setting here
				if (!(instant_leader_config.flag & ~alle->GetTargetConfig().flag))
				{
					instant_min_max_mp = instant_leader_config.min_max_mp;
					instant_max_max_mp = instant_leader_config.max_max_mp;
				}
			
				// note that the "init_config" here is not passed in as a parameter as it is always default
				int lower_min = 1;
				int lower_max = instant_max_max_mp;
				int upper_min = instant_min_max_mp;
				int upper_max = 9;

				variant = generate StatCondVariant(lower_min, lower_max, upper_min, upper_max);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4));
				alle->FillRep(rep);
				variant->FillRep(rep);
			}
			Detail = alle->DetailAlt6() + (alle->IsThirdPersonSingle() ? " has" : " have") + variant->Detail() + " Max MP";
			CreateNodeHardCopy = new maxMpCond(card_copy,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)),
				(StatCondVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			CheckThisValid
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					if (!variant->CheckStatValid(parent_card->owner->max_mp))
						return false;
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					if (!variant->CheckStatValid(parent_card->opponent->max_mp))
						return false;
				return true;
			}
		}
	
	BaseTargetedEff
	default:
		{
			preselector
			{
				if (target_mode == TARGET_MODE_LEADER)
				{
					forbid costModEff, destroyEff, discardEff, moveEff, copyEff, transformEff,
						changeToBeastEff, changeToDragonEff, changeToDemonEff, giveStealthEff;
				}
				else if (target_mode == TARGET_MODE_SELF)
				{
					if (self_config & TARGET_IS_LEADER)
					{
						forbid destroyEff, changeToBeastEff, changeToDragonEff, changeToDemonEff, giveStealthEff;
						if (!(self_config & TARGET_POS_HAND_OR_DECK)) // played leaders cannot be moved, copied, or transformed
							forbid moveEff, copyEff, transformEff;
					}
					else if (self_config & TARGET_IS_SPELL)
						forbid damageEff, healEff, resAtkTimesEff, atkHpModEff, destroyEff, atkTimesModEff, changeToBeastEff, changeToDragonEff, changeToDemonEff, giveChargeEff, giveTauntEff, giveStealthEff, giveShieldEff;

					// leader cards self directing effect when on the field can be covered by leader effect don't actually need self effect (to simplify the mechanism for avoiding trivial conditions)
					if (!(self_config & TARGET_NOT_LEADER))
						forbid damageEff, healEff, resAtkTimesEff;

					if (effect_timing == EFFECT_TIMING_TURN) // repeatedly modifying itself with something that is not easily changed isn't interesting
						forbid changeToBeastEff, changeToDragonEff, changeToDemonEff, giveChargeEff, giveTauntEff, giveUntargetableEff, givePoisonousEff, giveLifestealEff;

					// avoid modifying to something that is initially true, stealth and shield is a little bit special has they are easily lost 
					if (!(self_config & TARGET_NOT_BEAST))
						forbid changeToBeastEff;
					if (!(self_config & TARGET_NOT_DRAGON))
						forbid changeToDragonEff;
					if (!(self_config & TARGET_NOT_DEMON))
						forbid changeToDemonEff;
					if (self_config & TARGET_IS_CHARGE)
						forbid giveChargeEff;
					if (self_config & TARGET_IS_TAUNT)
						forbid giveTauntEff;
					if ((self_config & TARGET_IS_STEALTH) && effect_timing == EFFECT_TIMING_PLAY)
						forbid giveStealthEff;
					if (self_config & TARGET_IS_UNTARGETABLE)
						forbid giveUntargetableEff;
					if ((self_config & TARGET_IS_SHIELDED) && effect_timing == EFFECT_TIMING_PLAY)
						forbid giveShieldEff;
					if (self_config & TARGET_IS_POISONOUS)
						forbid givePoisonousEff;
					if (self_config & TARGET_IS_LIFESTEAL)
						forbid giveLifestealEff;
				}

				if (effect_depth >= max_eff_depth)
					forbid giveEffectsEff, transformEff;
			}
		}
	:=
	| damageEff: int val, DamageAttributes* attr // attr part doesn't need description here, it is only to contribute to attributes
		{
			generator 
			{
				val = GetRandInt(1, 10);
				if (give_eff)
					attr = construct damageAttributes(noPoisonous(), noLifesteal());
				else
					attr = generate DamageAttributes(self_config, target_mode, val);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0, <double>{NormalizeCode(val, 1, 10)}));
				attr->FillRep(rep);
			}
			Detail = "Deal " + IntToStr(val) + " damage to ";
			CreateNodeHardCopy = new damageEff(card_copy, val,
				(DamageAttributes*)(attr->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig = CHAR_COND_FILTER;
			GetTargetConfig = FIELD_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					target->TakeDamage(val, parent_card, start_of_batch);
					return target->is_dying;
				}
				return false;
			}
		}
	| healEff: int val
		{
			generator { val = GetRandInt(1, 10); }
			FillRep
			{
				rep.push_back(mkNodeRep(1, <double>{NormalizeCode(val, 1, 10)}));
			}
			Detail = "Restore " + IntToStr(val) + " health to ";
			CreateNodeHardCopy = new healEff(card_copy, val);
			GetGlobalSelfConfig = CHAR_COND_FILTER;
			GetTargetConfig = FIELD_COND_FILTER;
			TargetedAction 
			{ 
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
					target->RestoreHp(val);
				return false;
			}
		}
	| resAtkTimesEff: int val
		{
			generator { val = GetRandInt(1, 5); }
			FillRep
			{
				rep.push_back(mkNodeRep(2, <double>{NormalizeCode(val, 1, 5)}));
			}
			Detail = "Restore " + IntToStr(val) + " attack " + (val == 1 ? "time" : "times") + " to ";
			CreateNodeHardCopy = new resAtkTimesEff(card_copy, val);
			GetGlobalSelfConfig = CHAR_COND_FILTER;
			GetTargetConfig = FIELD_COND_FILTER;
			TargetedAction 
			{ 
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
					target->RestoreAtkTimes(val);
				return false;
			}
		}
	| costModEff{double inc_prob}: int val
		{
			generator
			{
				val = GetRandInt(1, 10);
				if (RandomRoll(1.0 - inc_prob) && (target_mode != TARGET_MODE_SELF || self_config.max_cost > 0))
				{
					val = -val;
					if (target_mode == TARGET_MODE_SELF && val < -self_config.max_cost)
						val = -self_config.max_cost;
				}
			}
			FillRep
			{
				rep.push_back(mkNodeRep(3, <double>{NormalizeCode(val, -10, 10)}));
			}
			Detail = "Give " + ((val < 0 ? "" : "+") + IntToStr(val)) + " to the cost of ";
			CreateNodeHardCopy = new costModEff(card_copy, val);
			GetGlobalSelfConfig = GetCostConfig(TARGET_TYPE_ANY, (val < 0 ? -val : 0), 10);
			GetTargetConfig = GetCostConfig(HAND_OR_DECK_COND_FILTER, (val < 0 ? -val : 0), 10);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
					target->ModifyCost(val);
				
				return false;
			}
		}
	| atkHpModEff: int atkmod, int hpmod
		{
			generator
			{
				atkmod = GetRandInt(-5, 5);
				if (target_mode == TARGET_MODE_SELF && atkmod < -self_config.max_atk)
					atkmod = -self_config.max_atk;
				if (atkmod == 0)
					hpmod = GetRandInt(1, 10); // having two zeros are pointless
				else
					hpmod = GetRandInt(0, 10);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4, <double>{NormalizeCode(atkmod, -5, 5), NormalizeCode(hpmod, 0, 10)}));
			}
			Detail = "Give " + ((atkmod < 0 ? "" : "+") + IntToStr(atkmod)) + "/" + ((hpmod < 0 ? "" : "+") + IntToStr(hpmod)) + " to ";
			CreateNodeHardCopy = new atkHpModEff(card_copy, atkmod, hpmod);
			GetTargetConfig = GetAtkConfig(CHAR_COND_FILTER, (atkmod < 0 ? -atkmod : 0), 10);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
					target->ModifyAtkHp(atkmod, hpmod);

				return false;
			}
		}
	| atkTimesModEff{double dec_prob}: int val
		{
			generator
			{
				val = GetRandInt(1, 3);
				if (RandomRoll(dec_prob) && (target_mode != TARGET_MODE_SELF || self_config.max_n_atks > 0))
				{
					val = -val;
					if (target_mode == TARGET_MODE_SELF && val < -self_config.max_n_atks)
						val = -self_config.max_n_atks;
				}
			}
			FillRep
			{
				rep.push_back(mkNodeRep(5, <double>{NormalizeCode(val, -3, 3)}));
			}
			Detail = "Give " + ((val < 0 ? "" : "+") + IntToStr(val)) + " to the attack times of ";
			CreateNodeHardCopy = new atkTimesModEff(card_copy, val);
			GetTargetConfig = GetAtkTimesConfig(CHAR_COND_FILTER, (val < 0 ? -val : 0), 5);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
					target->ModifyAtkTimes(val);

				return false;
			}
		}
	| destroyEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(6));
			}
			Detail = "Destroy ";
			CreateNodeHardCopy = new destroyEff(card_copy);
			GetGlobalSelfConfig = MINION_COND_FILTER;
			GetTargetConfig = TARGET_POS_FIELD | TARGET_IS_MINION | TARGET_ANY_ALLE_MINION_ATTR_TYPE;
			TargetedAction 
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					target->owner->FlagDestroy(target, start_of_batch);
					return true;
				}
				return false;
			}
		}
	| discardEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(7));
			}
			Detail = "Discard ";
			CreateNodeHardCopy = new discardEff(card_copy);
			GetGlobalSelfConfig
			{
				// leader and field cannot be allowed at the same time
				unsigned tmp_filter;
				if (!(self_config & TARGET_POS_HAND_OR_DECK))
					tmp_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER))
					tmp_filter = HAND_OR_DECK_COND_FILTER;
				else
					tmp_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return tmp_filter;
			}
			GetSelfConfig
			{
				// leader and field cannot be allowed at the same time
				unsigned tmp_filter;
				if (!(self_config & TARGET_POS_HAND_OR_DECK))
					tmp_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER))
					tmp_filter = HAND_OR_DECK_COND_FILTER;
				else
					tmp_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return tmp_filter;
			}
			GetTargetConfig = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER); // leader and field cannot be allowed at the same time
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					switch(target->card_pos)
					{
						case CARD_POS_AT_FIELD:
							target->owner->FlagFieldDiscard(target, start_of_batch);
							break;
						case CARD_POS_AT_HAND:
							target->owner->FlagHandDiscard(target, start_of_batch);
							break;
						case CARD_POS_AT_DECK:
							target->owner->FlagDeckDiscard(target, start_of_batch);
							break;
					}
					// it is necessary to consider discard in the batch mechanism, as it can trigger winGameEff, which is resolved immediately (no delay); in general this is a good generalizable practice
					return true;
				}
				return false;
			}
		}
	| moveEff: Destination* dest
		{
			generator { dest = generate Destination(self_config, target_mode, effect_timing, TARGET_MODE_MOVE_DEST); }
			FillRep
			{
				rep.push_back(mkNodeRep(8));
				dest->FillRep(rep);
			}
			Detail = dest->Detail();
			Suffix = dest->Suffix();
			CreateNodeHardCopy = new moveEff(card_copy, (Destination*)(dest->CreateNodeHardCopy(card_copy, redir_map)));
			GetPlayTargetConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned type_filter = dest_config | ~TARGET_ANY_CARD_TYPE;
				// should not move to the same position
				unsigned pos_complement_filter = ~(dest_config & TARGET_ANY_POS_TYPE);
 				unsigned alle_flag = dest_config & TARGET_ANY_ALLE_TYPE;
 				unsigned alle_complement_filter = ~alle_flag;
				unsigned dest_constraint_filter = type_filter;
				if (!alle_flag) // meaning the "owner" type destination
					dest_constraint_filter &= pos_complement_filter;
				else
					dest_constraint_filter &= (RandomRoll(NOT_POS_PARAM) ? pos_complement_filter : alle_complement_filter);
				if (!(dest_constraint_filter & TARGET_POS_HAND)) // if not at hand (has to be on the field for a targeted effect), only minions are possible
					dest_constraint_filter &= MINION_COND_FILTER;

				// leader and field cannot be allowed at the same time
				unsigned leader_constraint_filter;
				if(!(dest_constraint_filter & TARGET_IS_ALLY) || !(dest_constraint_filter & TARGET_POS_HAND)) // in this case the target has to be on the field, so we should forbid leader
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else // otherwise apply one of the constraints randomly
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER); // use HAND_COND_FILTER at the end would be the same as it would still be processed in the TargetCond part

				return dest_constraint_filter & leader_constraint_filter;
			}
			GetGlobalSelfConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned dest_constraint_filter = dest_config | ~TARGET_ANY_CARD_TYPE; // only the type matters because other parts can easily change (we want aspects that are unchangeable or hard to change)
				
				// leader and field cannot be allowed at the same time
				CondConfig self_config_copy = self_config;
				self_config_copy &= dest_constraint_filter;
				unsigned leader_constraint_filter;
				if (!(self_config_copy & TARGET_POS_HAND_OR_DECK))
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config_copy & TARGET_NOT_LEADER))
					leader_constraint_filter = HAND_OR_DECK_COND_FILTER;
				else
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return dest_constraint_filter & leader_constraint_filter;
			}
			GetSelfConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned type_filter = dest_config | ~TARGET_ANY_CARD_TYPE;
				// should not move to the same position
				unsigned pos_complement_filter = ~(dest_config & TARGET_ANY_POS_TYPE);
 				unsigned alle_flag = dest_config & TARGET_ANY_ALLE_TYPE;
 				unsigned alle_complement_filter = ~alle_flag;
				unsigned dest_constraint_filter = type_filter & ALLY_COND_FILTER; // this ally is because of self mode (doesn't really matter as the alle part in the source cond will be treated specially)
				if (!alle_flag || alle_flag == TARGET_IS_ALLY) // all zero-bits means the "owner" type destination
					dest_constraint_filter &= pos_complement_filter;
				
				// leader and field cannot be allowed at the same time
				CondConfig self_config_copy = self_config;
				self_config_copy &= dest_constraint_filter;
				unsigned leader_constraint_filter;
				if (!(self_config_copy & TARGET_POS_HAND_OR_DECK))
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config_copy & TARGET_NOT_LEADER))
					leader_constraint_filter = HAND_OR_DECK_COND_FILTER;
				else
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return dest_constraint_filter & leader_constraint_filter;
			}
			GetTargetConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned type_filter = dest_config | ~TARGET_ANY_CARD_TYPE;
				// should not move to the same position
				unsigned pos_complement_filter = ~(dest_config & TARGET_ANY_POS_TYPE);
				unsigned alle_flag = dest_config & TARGET_ANY_ALLE_TYPE;
 				unsigned alle_complement_filter = ~alle_flag;
				unsigned dest_constraint_filter = type_filter;
				if (!alle_flag) // meaning the "owner" type destination
					dest_constraint_filter &= pos_complement_filter;
				else
					dest_constraint_filter &= (RandomRoll(NOT_POS_PARAM) ? pos_complement_filter : alle_complement_filter);
				
				// leader and field cannot be allowed at the same time (note the dest_constraint_filter part never forbid both hand and deck, or force leader)
				unsigned leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				
				return dest_constraint_filter & leader_constraint_filter;
			}
			TargetedAction
			{
				Card* target = parent_card->owner->ExtractTargetCard(z);
				if (target && !target->is_dying)
				{
					dest->SubTargetedAction(target, parent_card, start_of_batch);
					// note, it is necessary to consider card movement/copy in the batch mechanism as the discard caused by them are considered in the same batch and can trigger winGameEff, which is resolved immediately (no delay); in general this is a good generalizable practice
					return true; 
				}
				return false;
			}
		}
	| copyEff: Destination* dest
		{
			generator { dest = generate Destination(self_config, target_mode, effect_timing, TARGET_MODE_COPY_DEST); }
			FillRep
			{
				rep.push_back(mkNodeRep(9));
				dest->FillRep(rep);
			}
			Detail = dest->Detail() + "a copy of ";
			DetailAlt1 = dest->Detail() + "copies of "; // for plural
			Suffix = dest->Suffix();
			CreateNodeHardCopy = new copyEff(card_copy, (Destination*)(dest->CreateNodeHardCopy(card_copy, redir_map)));
			GetPlayTargetConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned dest_constraint_filter = dest_config | ~TARGET_ANY_CARD_TYPE; // for copy, only the type matters (except we don't allow deck to deck copy, which isn't possible for targeted effect anyway)

                                // leader and field cannot be allowed at the same time (note the dest_constraint_filter part never forbid both hand and deck, or force leader)
                                // well, copying played leader to hand or deck could be OK but it doesn't hurt to forbid it, so we don't need to consider the possibility of adding battlecries to played leaders
                                unsigned leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

                                return dest_constraint_filter & leader_constraint_filter;
			}
			GetGlobalSelfConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned dest_constraint_filter = dest_config | ~TARGET_ANY_CARD_TYPE; // only the type matters because other parts can easily change (we want aspects that are unchangeable or hard to change)
				
				// leader and field cannot be allowed at the same time
                                // well, copying played leader to hand or deck could be OK but it doesn't hurt to forbid it, so we don't need to consider the possibility of adding battlecries to played leaders
				CondConfig self_config_copy = self_config;
				self_config_copy &= dest_constraint_filter;
				unsigned leader_constraint_filter;
				if (!(self_config_copy & TARGET_POS_HAND_OR_DECK))
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config_copy & TARGET_NOT_LEADER))
					leader_constraint_filter = HAND_OR_DECK_COND_FILTER;
				else
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return dest_constraint_filter & leader_constraint_filter;
			}
			GetSelfConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned dest_constraint_filter = dest_config | ~TARGET_ANY_CARD_TYPE; // for copy, only the type matters (except we don't allow deck to deck copy)
				// disallow deck to deck copy, to avoid deck size explosion (even with overheat mechanism and turn limit), because deck size is unbounded
				if (dest_config & TARGET_POS_DECK)
					dest_constraint_filter &= NOT_DECK_COND_FILTER;
				
				// leader and field cannot be allowed at the same time
                                // well, copying played leader to hand or deck could be OK but it doesn't hurt to forbid it, so we don't need to consider the possibility of adding battlecries to played leaders
				CondConfig self_config_copy = self_config;
				self_config_copy &= dest_constraint_filter;
				unsigned leader_constraint_filter;
				if (!(self_config_copy & TARGET_POS_HAND_OR_DECK))
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config_copy & TARGET_NOT_LEADER))
					leader_constraint_filter = HAND_OR_DECK_COND_FILTER;
				else
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return dest_constraint_filter & leader_constraint_filter;
			}
			GetTargetConfig
			{
				CondConfig dest_config = dest->GetTargetConfig();
				unsigned dest_constraint_filter = dest_config | ~TARGET_ANY_CARD_TYPE; // for copy, only the type matters (except we don't allow deck to deck copy)
				// disallow deck to deck copy, to avoid deck size explosion (even with overheat mechanism and turn limit), because deck size is unbounded
				if (dest_config & TARGET_POS_DECK)
					dest_constraint_filter &= NOT_DECK_COND_FILTER;
				
				// leader and field cannot be allowed at the same time (note the dest_constraint_filter part never forbid both hand and deck, or force leader)
				// well, copying played leader to hand or deck could be OK but it doesn't hurt to forbid it, so we don't need to consider the possibility of adding battlecries to played leaders
				unsigned leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				
				return dest_constraint_filter & leader_constraint_filter;
			}
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					dest->SubTargetedAction(target->CreateCopy(), parent_card, start_of_batch);
					// note, it is necessary to consider card movement/copy in the batch mechanism as the discard caused by them are considered in the same batch and can trigger winGameEff, which is resolved immediately (no delay); in general this is a good generalizable practice
					return true;
				}
				return false;
			}
		}
	| transformEff: NewCardVariant* variant
		{
			generator { variant = generate NewCardVariant(self_config, target_mode, effect_timing, effect_depth); }
			FillRep
			{
				rep.push_back(mkNodeRep(10));
				variant->FillRep(rep);
			}
			Detail = "Transform ";
			Suffix = " to " + variant->Detail();
			SuffixAlt1 = " to " + variant->DetailAlt1(); // for plural
			Postfix = variant->Postfix();
			PostfixIndent = variant->PostfixIndent(indent_size);
			CreateNodeHardCopy = new transformEff(card_copy, (NewCardVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				CondConfig variant_config = variant->GetTargetConfig();
				unsigned variant_constraint_filter = variant_config | ~TARGET_ANY_CARD_TYPE; // only the type matters because other parts can easily change (we want aspects that are unchangeable or hard to change)

				// leader and field cannot be allowed at the same time
				CondConfig self_config_copy = self_config;
				self_config_copy &= variant_constraint_filter;
				unsigned leader_constraint_filter;
				if (!(self_config_copy & TARGET_POS_HAND_OR_DECK))
					leader_constraint_filter = NOT_LEADER_COND_FILTER;
				else if (!(self_config_copy & TARGET_NOT_LEADER))
					leader_constraint_filter = HAND_OR_DECK_COND_FILTER;
				else
					leader_constraint_filter = (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);

				return variant_constraint_filter & leader_constraint_filter;
				
			}
			GetTargetConfig = variant->GetTargetConfig(); // the variant will either force it to be minion on the field, or force hand or deck, so there's no need to do the extra leader constraint
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					Card* card = variant->GetRelatedCard(parent_card);
					// cannot replace and delete target here because in case itself get transformed (through aoeEff, randEff, or selfEff) and there are more effects to trigger on the card at the same instant
					target->owner->FlagCardTransform(target, start_of_batch, card);
					// note, transform event cannot add to the potential draw through AoE etc. but as a generalizable practice, we still have it in the batch mechanism (any delayed event is considered in there)
					return true;
				}
				return false;
			}
		}
	| changeToBeastEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(11));
			}
			Detail = "Change the minion type of ";
			DetailAlt1 = "Change the minion types of "; // for plural
			Suffix = " to Beast";
			SuffixAlt1 = " to Beasts"; // for plural
			CreateNodeHardCopy = new changeToBeastEff(card_copy);
			GetTargetConfig = NOT_BEAST_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << target->owner->name << "\'s " << target->name << " minion type set to Beast." << endl;
					#endif
					target->minion_type = BEAST_MINION;
				}
				return false;
			}
		}
	| changeToDragonEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(12));
			}
			Detail = "Change the minion type of ";
			DetailAlt1 = "Change the minion types of "; // for plural
			Suffix = " to Dragon";
			SuffixAlt1 = " to Dragons"; // for plural
			CreateNodeHardCopy = new changeToDragonEff(card_copy);
			GetTargetConfig = NOT_DRAGON_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << target->owner->name << "\'s " << target->name << " minion type set to Dragon." << endl;
					#endif
					target->minion_type = DRAGON_MINION;
				}
				return false;
			}
		}
	| changeToDemonEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(13));
			}
			Detail = "Change the minion type of ";
			DetailAlt1 = "Change the minion types of "; // for plural
			Suffix = " to Demon";
			SuffixAlt1 = " to Demons"; // for plural
			CreateNodeHardCopy = new changeToDemonEff(card_copy);
			GetTargetConfig = NOT_DEMON_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << target->owner->name << "\'s " << target->name << " minion type set to Demon." << endl;
					#endif
					target->minion_type = DEMON_MINION;
				}
				return false;
			}
		}
	| giveChargeEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(14));
			}
			Detail = "Grant Charge to ";
			CreateNodeHardCopy = new giveChargeEff(card_copy);
			GetTargetConfig = NOT_CHARGE_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Change attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_charge = true;
				}
				return false;
			}
		}
	| giveTauntEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(15));
			}
			Detail = "Grant Taunt to ";
			CreateNodeHardCopy = new giveTauntEff(card_copy);
			GetTargetConfig = NOT_TAUNT_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Taunt attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_taunt = true;
				}
				return false;
			}
		}
	| giveStealthEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(16));
			}
			Detail = "Grant Stealth to ";
			CreateNodeHardCopy = new giveStealthEff(card_copy);
			GetGlobalSelfConfig = (effect_timing == EFFECT_TIMING_PLAY ? NOT_STEALTH_COND_FILTER : MINION_COND_FILTER);
			GetSelfConfig = TARGET_POS_FIELD | TARGET_IS_MINION | TARGET_NOT_STEALTH | TARGET_ANY_ALLE_MINION_TYPE; // make sure giving itself stealth or shield only possible on the field (for turn start and end effect, as these attributes only lose easily on the field)
			GetTargetConfig = NOT_STEALTH_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Stealth attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_stealth = true;
				}
				return false;
			}
		}
	| giveUntargetableEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(17));
			}
			Detail = "Grant Untargetability to ";
			CreateNodeHardCopy = new giveUntargetableEff(card_copy);
			GetTargetConfig = NOT_UNTARGETABLE_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Untargetability attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_untargetable = true;
				}
				return false;
			}
		}
	| giveShieldEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(18));
			}
			Detail = "Grant Shield to ";
			CreateNodeHardCopy = new giveShieldEff(card_copy);
			GetGlobalSelfConfig = (effect_timing == EFFECT_TIMING_PLAY ? NOT_SHIELDED_COND_FILTER : CHAR_COND_FILTER);
			GetSelfConfig = TARGET_POS_FIELD | TARGET_ANY_CHAR | TARGET_NOT_SHIELDED | TARGET_ANY_ALLE_MINION_TYPE; // make sure giving itself stealth or shield only possible on the field (for turn start and end effect, as these attributes only lose easily on the field)
			GetTargetConfig = NOT_SHIELDED_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Divine Shield attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_shielded = true;
				}
				return false;
			}
		}
	| givePoisonousEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(19));
			}
			Detail = "Grant Poisonous to ";
			CreateNodeHardCopy = new givePoisonousEff(card_copy);
			GetTargetConfig = NOT_POISONOUS_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Poisonous attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_poisonous = true;
				}
				return false;
			}
		}
	| giveLifestealEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(20));
			}
			Detail = "Grant Lifesteal to ";
			CreateNodeHardCopy = new giveLifestealEff(card_copy);
			GetTargetConfig = NOT_LIFESTEAL_COND_FILTER;
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Lifesteal attribute given to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_lifesteal = true;
				}
				return false;
			}
		}
	| rmAttributesEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(21));
			}
			Detail = "Remove all attribute keywords from ";
			CreateNodeHardCopy = new rmAttributesEff(card_copy);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Attribute keywords removed from " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->is_charge = false;
					target->is_taunt = false;
					target->is_stealth = false;
					target->is_untargetable = false;
					target->is_shielded = false;
					target->is_poisonous = false;
					target->is_lifesteal = false;
				}
				return false;
			}
		}
	| setOverheatEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(22));
			}
			Detail = "Set every effect on ";
			Suffix = " to overheat";
			CreateNodeHardCopy = new setOverheatEff(card_copy);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Every effect on " << target->owner->name << "\'s " << target->name << " set to overheat." << endl;
					#endif
					target->SetAllOverheatCounts(MAX_OVERHEAT_THRESHOLD);
				}
				return false;
			}
		}
	| decOhThresholdEff: int val
		{
			generator { val = GetRandInt(1, 5); }
			FillRep
			{
				rep.push_back(mkNodeRep(23, <double>{NormalizeCode(val, 1, 5)}));
			}
			Detail = "Reduce the overheat threshold for every effect on ";
			Suffix = " by " + IntToStr(val) + " (applied repeatedly for duplicated effects)";
			CreateNodeHardCopy = new decOhThresholdEff(card_copy, val);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "The overheat threshhold for every effects on " << target->owner->name << "\'s " << target->name << " reduced by " << IntToStr(val) << "." << endl;
					#endif
					target->ModAllOverheatThresholds(-val);
				}
				return false;
			}
		}
	| resetStateEff:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(24));
			}
			Detail = "Reset ";
			Suffix = " to its original state (not directly applying to the sleeping state, consumed attack times, and overheat counts)"; // if it is related to Charge, sleeping state may change indirectly though
			SuffixAlt1 = " to their original states (not directly applying to sleeping states, consumed attack times, and overheat counts)"; // plural
			CreateNodeHardCopy = new resetStateEff(card_copy);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << target->owner->name << "\'s " << target->name << " set to its original state." << endl;
					#endif
					target->mana = target->orig_mana;
					target->atk = target->orig_atk;
					target->max_hp = target->orig_hp;
					target->hp_loss = 0;
					target->max_n_atks = target->orig_n_atks;
					target->minion_type = target->orig_minion_type;
					target->is_charge = target->orig_is_charge;
					target->is_taunt = target->orig_is_taunt;
					target->is_stealth = target->orig_is_stealth;
					target->is_untargetable = target->orig_is_untargetable;
					target->is_shielded = target->orig_is_shielded;
					target->is_poisonous = target->orig_is_poisonous;
					target->is_lifesteal = target->orig_is_lifesteal;
					target->owner->FlagCardReset(target, start_of_batch); // need deferred mechanism, in case this is on an extra effect and reset the card itself (through aoeEff, randEff, selfEff, leaderEff etc.)
					target->SetAllOverheatThresholds(DEFAULT_OVERHEAT_THRESHOLD);
					return true;	
				}
				return false;
			}
		}
	| giveEffectsEff: SpecialEffects* effects 
		{
			generator
			{
				int next_depth = effect_depth + 1;
				int min_num_effs = 1;
				int max_num_effs = max_eff_num >> next_depth;
				CondConfig tmp_config = GetDefaultInitConfig();
				if (target_mode == TARGET_MODE_LEADER)
				{
					tmp_config &= LEADER_COND_FILTER;
					tmp_config &= FIELD_COND_FILTER;
				}
				else if (target_mode == TARGET_MODE_SELF)
					tmp_config = self_config;
				effects = generate SpecialEffects(tmp_config, min_num_effs, max_num_effs, next_depth, true);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(25));
				effects->FillRep(rep);
			}
			Detail = "Give the following effect(s) to ";
			Postfix = "\n" + effects->DetailIndent(4);
			PostfixIndent = "\n" + effects->DetailIndent(indent_size + 4); 
			CreateNodeHardCopy = new giveEffectsEff(card_copy, (SpecialEffects*)(effects->CreateNodeHardCopy(card_copy, redir_map)));
			GetTargetConfig = effects->GetGlobalSelfConfig(GetDefaultInitConfig(), EFFECT_TIMING_DEFAULT);
			TargetedAction
			{
				Card* target = parent_card->owner->GetTargetCard(z);
				if (target && !target->is_dying)
				{
					#ifndef SUPPRESS_ALL_MSG
					if (!parent_card->owner->is_exploration)
						cout << "Extra effects granted to " << target->owner->name << "\'s " << target->name << endl;
					#endif
					target->AddExtraEffects(effects);
				}
				return false;
			}
			destructor
			{
				effects->num_refs--;
				if (effects->num_refs <= 0)
					delete effects;
			}
		}

	BaseUntargetedEff
	default:
		{
			preselector
			{
				if (effect_timing == EFFECT_TIMING_DESTROY || effect_timing == EFFECT_TIMING_DISCARD || // deathrattle and on-discard effects should not be directed to itself
					((self_config & TARGET_IS_SPELL) && effect_timing == EFFECT_TIMING_PLAY) || // spell play effect should not be directed to itself
					(!(self_config & TARGET_NOT_LEADER) && !(self_config & TARGET_POS_HAND_OR_DECK))) // leader cards self directing effect when on the field can be covered by leader effect don't actually need self effect (to simplify the mechanism for avoiding trivial conditions)
					forbid selfEff;

				if (effect_depth >= max_eff_depth)
					forbid newEff; 
			}
		}
	:=
	| aoeEff: BaseTargetedEff* effect, TargetCond* cond
		{
			generator
			{
				effect = generate BaseTargetedEff(self_config, TARGET_MODE_DEFAULT, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				cond = generate TargetCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				effect->FillRep(rep);
				cond->FillRep(rep);
			}
			Detail = effect->DetailAlt1() + "all " + cond->DetailAlt2() + effect->SuffixAlt1();
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new aoeEff(card_copy,
				(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(TargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			UntargetedAction
			{
				bool start_of_batch = true;
				int total_cards = 2 + parent_card->owner->field.size() + parent_card->owner->hand.size() + parent_card->owner->deck.size()
					+ parent_card->opponent->field.size() + parent_card->opponent->hand.size() + parent_card->opponent->deck.size();
				for (int i = 0; i < total_cards; i++)
				{
					Card* target = parent_card->owner->GetTargetCard(i);
					if (target && !target->is_dying && cond->CheckCardValid(target, parent_card)) // even that target && target->is_dying is checked in TargetedAction, checking here still helps batching
						start_of_batch = !effect->TargetedAction(i, parent_card, start_of_batch) && start_of_batch; // note the order of the operands for && cannot be inverted, because shortcut mechanism may skip the action part otherwise
				}
			}
		}
	| randEff: BaseTargetedEff* effect, TargetCond* cond
		{
			generator
			{
				effect = generate BaseTargetedEff(self_config, TARGET_MODE_DEFAULT, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				cond = generate TargetCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				effect->FillRep(rep);
				cond->FillRep(rep);
			}
			Detail = effect->Detail() + "a random " + cond->Detail() + effect->Suffix();
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new randEff(card_copy,
				(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(TargetCond*)(cond->CreateNodeHardCopy(card_copy, redir_map)));
			UntargetedAction
			{
				int total_cards = 2 + parent_card->owner->field.size() + parent_card->owner->hand.size() + parent_card->owner->deck.size()
					+ parent_card->opponent->field.size() + parent_card->opponent->hand.size() + parent_card->opponent->deck.size();
				int* candidates = new int[total_cards];
				int tmp_num = 0;
				for (int i = 0; i < total_cards; i++)
				{
					Card* target = parent_card->owner->GetTargetCard(i);
					if (target && !target->is_dying && cond->CheckCardValid(target, parent_card))
						candidates[tmp_num++] = i;
				}
				if (tmp_num > 0)
				{
					int chosen_index = GetRandInt(tmp_num);
					effect->TargetedAction(candidates[chosen_index], parent_card, true);
				}
				delete [] candidates;
			}
		}
	| leaderEff: BaseTargetedEff* effect, AllegianceCond* alle
		{
			generator
			{
				effect = generate BaseTargetedEff(self_config, TARGET_MODE_LEADER, effect_timing, effect_depth, give_eff);

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = effect->GetTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_LEADER, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				effect->FillRep(rep);
				alle->FillRep(rep);
			}
			Detail = (alle->IsPlural() ? effect->DetailAlt1() + alle->DetailAlt4() + effect->SuffixAlt1() : effect->Detail() + alle->DetailAlt4() + effect->Suffix());
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new leaderEff(card_copy,
				(BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)),
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetLeaderConfig
			{
				CondConfig tmp_config = effect->GetTargetConfig();
				tmp_config &= alle->GetTargetConfig(); // used to distinguish which side(s) this is applied on
				return tmp_config;
			}
			UntargetedAction
			{
				bool start_of_batch = true;
				Card* target_a = parent_card->owner->leader;
				if (!target_a->is_dying && alle->CheckCardValid(target_a, parent_card))
					start_of_batch = !effect->TargetedAction(0, parent_card, true) && start_of_batch; // note the order of the operands for && cannot be inverted, because shortcut mechanism may skip the action part otherwise
				Card* target_b = parent_card->opponent->leader;
				if (!target_b->is_dying && alle->CheckCardValid(target_b, parent_card))
					effect->TargetedAction(parent_card->owner->field.size() + parent_card->opponent->field.size() + 1, parent_card, start_of_batch);
			}
		}
	| selfEff: BaseTargetedEff* effect
		{
			generator { effect = generate BaseTargetedEff(self_config, TARGET_MODE_SELF, effect_timing, effect_depth, give_eff); }
			FillRep
			{
				rep.push_back(mkNodeRep(3));
				effect->FillRep(rep);
			}
			Detail = effect->Detail() + "itself" + effect->Suffix();
			Postfix = effect->Postfix();
			PostfixIndent = effect->PostfixIndent(indent_size);
			CreateNodeHardCopy = new selfEff(card_copy, (BaseTargetedEff*)(effect->CreateNodeHardCopy(card_copy, redir_map)));
			GetGlobalSelfConfig
			{
				CondConfig tmp_config = effect->GetGlobalSelfConfig(self_config, effect_timing);
				// leader and field shall not be selected at the same time if there is self targetting effect (leader card is special in that they cannot change their place anymore after being placed)
				if (!(self_config & TARGET_POS_HAND_OR_DECK) || !(tmp_config & TARGET_POS_HAND_OR_DECK))
					tmp_config &= NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER) || !(tmp_config & TARGET_NOT_LEADER)) 
					tmp_config &= HAND_OR_DECK_COND_FILTER;
				else
					tmp_config &= (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				return tmp_config;
			}
			GetSelfConfig
			{
				CondConfig tmp_config = effect->GetSelfConfig(self_config);
				// leader cards self directing effect when on the field can be covered by leader effect don't actually need self effect (to simplify the mechanism for avoiding trivial conditions)
				if (!(self_config & TARGET_POS_HAND_OR_DECK) || !(tmp_config & TARGET_POS_HAND_OR_DECK))
					tmp_config &= NOT_LEADER_COND_FILTER;
				else if (!(self_config & TARGET_NOT_LEADER) || !(tmp_config & TARGET_NOT_LEADER)) 
					tmp_config &= HAND_OR_DECK_COND_FILTER;
				else
					tmp_config &= (RandomRoll(NOT_LEADR_PARAM) ? NOT_LEADER_COND_FILTER : HAND_OR_DECK_COND_FILTER);
				return tmp_config;
			}
			UntargetedAction
			{
				if (!parent_card->is_dying)
					effect->TargetedAction(parent_card->GetTargetIndex(), parent_card, true);
			}
		}
	| drawCardEff: int val, AllegianceCond* alle
		{
			generator 
			{
				val = 10/GetRandInt(3, 10); // 1 ~ 3 biased

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4, <double>{NormalizeCode(val, 1, 3)}));
				alle->FillRep(rep);
			}
			Detail = alle->DetailAlt5() + (alle->IsThirdPersonSingle() ? "draws " : "draw ") + IntToStr(val) + (val == 1 ? " card" : " cards");
			CreateNodeHardCopy = new drawCardEff(card_copy, val,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			UntargetedAction
			{
				bool start_of_batch = true;
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					for (int i = 0; i < val; i++)
					{
						parent_card->owner->DrawCard(start_of_batch);
						start_of_batch = false;
					}
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					for (int i = 0; i < val; i++)
					{
						parent_card->opponent->DrawCard(start_of_batch);
						start_of_batch = false;
					}
			}
		}
	| mpEff{double dec_prob}: int val, AllegianceCond* alle
		{
			generator
			{
				val = 200/GetRandInt(18, 100); // 1 ~ 10 biased
				if (RandomRoll(dec_prob))
					val = -val;

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref		
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(5, <double>{NormalizeCode(val, -10, 10)}));
				alle->FillRep(rep);
			}
			Detail = alle->DetailAlt5() + (val >= 0 ? "recover" : "exhaust") + (alle->IsThirdPersonSingle() ? "s " : " ") + IntToStr(abs(val)) + " MP";
			CreateNodeHardCopy = new mpEff(card_copy, val,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetLeaderConfig
			{
				CondConfig tmp_config;
				if (val < 0)
					tmp_config = GetMpConfig(-val, 10);
				else
					tmp_config = GetMpConfig(0, 10 - val);
				tmp_config &= alle->GetTargetConfig(); // used to distinguish which side(s) this is applied on
				return tmp_config;
			}
			UntargetedAction
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					parent_card->owner->ModifyMp(val);
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					parent_card->opponent->ModifyMp(val);
			}
		}
	| maxMpEff{double dec_prob}: int val, AllegianceCond* alle
		{
			generator
			{
				val = 100/GetRandInt(18, 100); // 1 ~ 5 biased
				if (RandomRoll(dec_prob))
					val = -val;

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_DEFAULT, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(6, <double>{NormalizeCode(val, -5, 5)}));
				alle->FillRep(rep);
			}
			Detail = alle->DetailAlt5() + (val >= 0 ? "gain" : "lose") + (alle->IsThirdPersonSingle() ? "s " : " ") + IntToStr(abs(val)) + " Max MP (and MP)";
			CreateNodeHardCopy = new maxMpEff(card_copy, val,
				(AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetLeaderConfig
			{
				CondConfig tmp_config;
				if (val < 0)
					tmp_config = GetMaxMpConfig(-val, 10);
				else
					tmp_config = GetMaxMpConfig(0, 10 - val);
				tmp_config &= alle->GetTargetConfig(); // used to distinguish which side(s) this is applied on
				return tmp_config;
			}
			UntargetedAction
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					parent_card->owner->ModifyMaxMp(val);
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					parent_card->opponent->ModifyMaxMp(val);
			}
		}
	| newEff: int val, Destination* dest, NewCardVariant* variant
		{
			generator
			{
				val = 120/GetRandInt(16, 120); // 1 ~ 7, biased to small numbers

				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				dest = generate Destination(tmp_init_config, TARGET_MODE_NEW, effect_timing, TARGET_MODE_NEW_DEST);
				CondConfig tmp_config = dest->GetTargetConfig(); // to counter the problem of rvalue passed to lvalue ref
				variant = generate NewCardVariant(tmp_config, TARGET_MODE_NEW, effect_timing, effect_depth);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(7, <double>{NormalizeCode(val, 1, 7)}));
				dest->FillRep(rep);
				variant->FillRep(rep);
			}
			Detail = dest->Detail() + (val == 1 ? variant->Detail() : IntToStr(val) + " " + variant->DetailAlt1()) + dest->Suffix();
			Postfix = variant->Postfix();
			PostfixIndent = variant->PostfixIndent(indent_size);
			CreateNodeHardCopy = new newEff(card_copy, val,
				(Destination*)(dest->CreateNodeHardCopy(card_copy, redir_map)),
				(NewCardVariant*)(variant->CreateNodeHardCopy(card_copy, redir_map)));
			UntargetedAction
			{
				bool start_of_batch = true;
				for (int i = 0; i < val; i++)
				{
					Card* card = variant->GetRelatedCard(parent_card);
					card->owner = parent_card->owner;
					card->opponent = parent_card->opponent;
					dest->SubTargetedAction(card, parent_card, start_of_batch);
					start_of_batch = false;
				}
			}
		}
	| winGameEff: AllegianceCond* alle
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig(); // to counter the problem of rvalue passed to lvalue ref
				alle = generate AllegianceCond(tmp_init_config, tmp_config, TARGET_MODE_WIN_GAME, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(8));
				alle->FillRep(rep);
			}
			Detail = alle->DetailAlt5() + "win" + (alle->IsThirdPersonSingle() ? "s " : " ") + "the game"; // well we don't actually want to have both players win the game but at least this is left as a possibility for constructed cards
			CreateNodeHardCopy = new winGameEff(card_copy, (AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			UntargetedAction
			{
				Card* target_a = parent_card->owner->leader;
				if (alle->CheckCardValid(target_a, parent_card))
					parent_card->opponent->SetLose();
				Card* target_b = parent_card->opponent->leader;
				if (alle->CheckCardValid(target_b, parent_card))
					parent_card->owner->SetLose();
			}
		}


	Destination
	default:
		{
			preselector
			{
				if (target_mode == TARGET_MODE_SELF)
				{
					if ((self_config & TARGET_IS_LEADER) || (self_config & TARGET_IS_SPELL))
						forbid fieldDest, ownerFieldDest;
					if (dest_mode == TARGET_MODE_MOVE_DEST)
					{
						if(!(self_config & TARGET_POS_HAND_OR_DECK))
							forbid ownerFieldDest;
						if(!(self_config & TARGET_NOT_HAND))
							forbid ownerHandDest;
						if(!(self_config & TARGET_NOT_DECK))
							forbid ownerDeckDest;
					}
					else if (dest_mode == TARGET_MODE_COPY_DEST)
					{
						if(!(self_config & TARGET_NOT_DECK)) // forbid deck to deck copy
							forbid deckDest, ownerDeckDest;
					}
				}

				if (target_mode = TARGET_MODE_NEW)
				{
					forbid ownerFieldDest, ownerHandDest, ownerDeckDest;
				}
			}
		}
	:=
	| fieldDest: AllegianceCond* alle
		{
			generator 
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig();
				if (target_mode == TARGET_MODE_SELF && dest_mode == TARGET_MODE_MOVE_DEST && !(self_config & TARGET_POS_HAND_OR_DECK))
					tmp_config = OPPO_COND_FILTER;
				alle = generate AllegianceCond(tmp_init_config, tmp_config, dest_mode, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				alle->FillRep(rep);
			}
			Detail = "Summon ";
			Suffix = " to " + alle->DetailAlt2() + (alle->IsPlural() ? "fields" : "field");
			CreateNodeHardCopy = new fieldDest(card_copy, (AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetTargetConfig = alle->GetTargetConfig() & FIELD_COND_FILTER & MINION_COND_FILTER; // this is not really config for cards but rather the config for the destination (or what the card would end up like after being moved/added)
			SubTargetedAction
			{
				bool is_ally = alle->CheckCardValid(parent_card->owner->leader, parent_card);
				bool is_opponent = alle->CheckCardValid(parent_card->opponent->leader, parent_card);
				if (is_ally)
				{
					parent_card->owner->FlagFieldSummon(target, start_of_batch);
					if (is_opponent) // if both ally and opponent apply, create a new copy
						parent_card->opponent->FlagFieldSummon(target->CreateCopy(), false);
				}
				else
				{
					if (is_opponent)
						parent_card->opponent->FlagFieldSummon(target, start_of_batch);
				}
			}
		}
	| ownerFieldDest:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(1));
			}
			Detail = "Summon ";
			Suffix = " to its owner's field";
			SuffixAlt1 = " to their owners' fields"; // for plural
			CreateNodeHardCopy = new ownerFieldDest(card_copy);
			GetTargetConfig = ~TARGET_ANY_ALLE_TYPE & FIELD_COND_FILTER & MINION_COND_FILTER; // we use all zero bits for allegiance to indicate the "owner" versions
			SubTargetedAction
			{
				target->owner->FlagFieldSummon(target, start_of_batch);
			}
		}
	| handDest: AllegianceCond* alle
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig();
				if (target_mode == TARGET_MODE_SELF && dest_mode == TARGET_MODE_MOVE_DEST && !(self_config & TARGET_NOT_HAND))
					tmp_config = OPPO_COND_FILTER;
				alle = generate AllegianceCond(tmp_init_config, tmp_config, dest_mode, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				alle->FillRep(rep);
			}
			Detail = "Put ";
			Suffix = " to " + alle->DetailAlt2() + (alle->IsPlural() ? "hands" : "hand");
			CreateNodeHardCopy = new handDest(card_copy, (AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetTargetConfig = alle->GetTargetConfig() & HAND_COND_FILTER; // this is not really config for cards but rather the config for the destination (or what the card would end up like after being moved/added)
			SubTargetedAction
			{
				bool is_ally = alle->CheckCardValid(parent_card->owner->leader, parent_card);
				bool is_opponent = alle->CheckCardValid(parent_card->opponent->leader, parent_card);
				if (is_ally)
				{
					parent_card->owner->FlagHandPut(target, start_of_batch);
					if (is_opponent) // if both ally and opponent apply, create a new copy
						parent_card->opponent->FlagHandPut(target->CreateCopy(), false);
				}
				else
				{
					if (is_opponent)
						parent_card->opponent->FlagHandPut(target, start_of_batch);
				}
			}
		}
	| ownerHandDest:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(3));
			}
			Detail = "Put ";
			Suffix = " to its owner's hand";
			SuffixAlt1 = " to their owners' hands"; // for plural
			CreateNodeHardCopy = new ownerHandDest(card_copy);
			GetTargetConfig = ~TARGET_ANY_ALLE_TYPE & HAND_COND_FILTER; // we use all zero bits for allegiance to indicate the "owner" versions
			SubTargetedAction
			{
				target->owner->FlagHandPut(target, start_of_batch);
			}
		}
	| deckDest: AllegianceCond* alle
		{
			generator
			{
				CondConfig tmp_init_config = GetDefaultInitConfig(); // to counter the problem of rvalue passed to lvalue ref
				CondConfig tmp_config = GetDefaultConfig();
				if (target_mode == TARGET_MODE_SELF && dest_mode == TARGET_MODE_MOVE_DEST && !(self_config & TARGET_NOT_DECK))
					tmp_config = OPPO_COND_FILTER;
				alle = generate AllegianceCond(tmp_init_config, tmp_config, dest_mode, effect_timing);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(4));
				alle->FillRep(rep);
			}
			Detail = "Shuffle ";
			Suffix = " to " + alle->DetailAlt2() + (alle->IsPlural() ? "decks" : "deck");
			CreateNodeHardCopy = new deckDest(card_copy, (AllegianceCond*)(alle->CreateNodeHardCopy(card_copy, redir_map)));
			GetTargetConfig = alle->GetTargetConfig() & DECK_COND_FILTER; // this is not really config for cards but rather the config for the destination (or what the card would end up like after being moved/added)
			SubTargetedAction
			{
				bool is_ally = alle->CheckCardValid(parent_card->owner->leader, parent_card);
				bool is_opponent = alle->CheckCardValid(parent_card->opponent->leader, parent_card);
				if (is_ally)
				{
					parent_card->owner->FlagDeckShuffle(target, start_of_batch);
					if (is_opponent) // if both ally and opponent apply, create a new copy
						parent_card->opponent->FlagDeckShuffle(target->CreateCopy(), false);
				}
				else
				{
					if (is_opponent)
						parent_card->opponent->FlagDeckShuffle(target, start_of_batch);
				}
			}
		}
	| ownerDeckDest:
		{
			FillRep
			{
				rep.push_back(mkNodeRep(5));
			}
			Detail = "Shuffle ";
			Suffix = " to its owner's deck";
			SuffixAlt1 = " to their owners' decks"; // for plural
			CreateNodeHardCopy = new ownerDeckDest(card_copy);
			GetTargetConfig = ~TARGET_ANY_ALLE_TYPE & DECK_COND_FILTER; // we use all zero bits for allegiance to indicate the "owner" versions
			SubTargetedAction
			{
				target->owner->FlagDeckShuffle(target, start_of_batch);
			}
		}

	NewCardVariant
	default:
		{
			preselector
			{
				if (target_mode == TARGET_MODE_SELF || target_mode == TARGET_MODE_NEW) // the new mode uses self_config for the config from selecting destination
				{
					if (!(self_config & TARGET_POS_FIELD) || !(self_config & TARGET_NOT_LEADER)) // the second half makes sure not transforming played leaders
						forbid plainMinion, fixedMinion, randomMinion;
					if (!(self_config & TARGET_POS_HAND_OR_DECK))
						forbid plainMinionCard, fixedCard, randomCard;
				}
			}
		}
	:=
	| plainMinionCard: Card* card
		{
			generator { card = CreatePlainMinion(name); }
			FillRep
			{
				rep.push_back(mkNodeRep(0));
				card->FillRep(rep);
			}
			Detail = "a " + IntToStr(card->orig_mana) + "/" + IntToStr(card->orig_atk) + "/" + IntToStr(card->orig_hp) + " " + MinionTypeDescription(card->minion_type) + " minion card"
					+ AttributeDescriptionInline(card->orig_is_charge, card->orig_is_taunt, card->orig_is_stealth, card->orig_is_untargetable, card->orig_is_shielded, card->orig_is_poisonous, card->orig_is_lifesteal);
			DetailAlt1 = IntToStr(card->orig_mana) + "/" + IntToStr(card->orig_atk) + "/" + IntToStr(card->orig_hp) + " " + MinionTypeDescription(card->minion_type) + " minion cards"
					+ AttributeDescriptionInline(card->orig_is_charge, card->orig_is_taunt, card->orig_is_stealth, card->orig_is_untargetable, card->orig_is_shielded, card->orig_is_poisonous, card->orig_is_lifesteal); // for plural
			CreateNodeHardCopy = new plainMinionCard(card_copy, card->CreateHardCopy(redir_map));
			GetTargetConfig = HAND_OR_DECK_COND_FILTER; // note: do not need MINION_COND_FITLER as the target (for a transform effect does not have to be minion card)
			GetRelatedCard = card->CreateCopy();
		}
	| plainMinion: Card* card
		{
			generator { card = CreatePlainMinion(name); }
			FillRep
			{
				rep.push_back(mkNodeRep(1));
				card->FillRep(rep);
			}
			Detail = "a " + IntToStr(card->orig_mana) + "/" + IntToStr(card->orig_atk) + "/" + IntToStr(card->orig_hp) + " " + MinionTypeDescription(card->minion_type) + " minion"
					+ AttributeDescriptionInline(card->orig_is_charge, card->orig_is_taunt, card->orig_is_stealth, card->orig_is_untargetable, card->orig_is_shielded, card->orig_is_poisonous, card->orig_is_lifesteal);
			DetailAlt1 = IntToStr(card->orig_mana) + "/" + IntToStr(card->orig_atk) + "/" + IntToStr(card->orig_hp) + " " + MinionTypeDescription(card->minion_type) + " minions"
					+ AttributeDescriptionInline(card->orig_is_charge, card->orig_is_taunt, card->orig_is_stealth, card->orig_is_untargetable, card->orig_is_shielded, card->orig_is_poisonous, card->orig_is_lifesteal); // for plural
			CreateNodeHardCopy = new plainMinion(card_copy, card->CreateHardCopy(redir_map));
			GetTargetConfig = MINION_COND_FILTER & FIELD_COND_FILTER;
			GetRelatedCard 
			{
				Card* card_copy = card->CreateCopy();
				return card_copy;
			}
		}
	| fixedCard: Card* card
		{
			generator
			{
				int next_depth = effect_depth + 1;
				int min_num_effs = 1;
				int max_num_effs = max_eff_num >> next_depth;
				card = CreateRandomCard(name, GetRandInt(0, 10), min_num_effs, max_num_effs, next_depth);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(2));
				card->FillRep(rep);
			}
			Detail = "a copy of the following card";
			DetailAlt1 = "copies of the following card"; // for plural
			Postfix = "\n" + card->DetailIndent(4);
			PostfixIndent = "\n" + card->DetailIndent(indent_size + 4);
			CreateNodeHardCopy = new fixedCard(card_copy, card->CreateHardCopy(redir_map));
			GetTargetConfig = HAND_OR_DECK_COND_FILTER;
			GetRelatedCard = card->CreateCopy();
		}
	| fixedMinion: Card* card
		{
			generator
			{ 
				int next_depth = effect_depth + 1;
				int min_num_effs = 1;
				int max_num_effs = max_eff_num >> next_depth;
				card = CreateRandomMinion(name, GetRandInt(0, 10), min_num_effs, max_num_effs, next_depth);
			}
			FillRep
			{
				rep.push_back(mkNodeRep(3));
				card->FillRep(rep);
			}
			Detail = "a copy the following minion";
			DetailAlt1 = "copies of the following minion"; // for plural
			Postfix = "\n" + card->DetailIndent(4);
			PostfixIndent = "\n" + card->DetailIndent(indent_size + 4);
			CreateNodeHardCopy = new fixedMinion(card_copy, card->CreateHardCopy(redir_map));
			GetTargetConfig = MINION_COND_FILTER & FIELD_COND_FILTER;
			GetRelatedCard 
			{
				Card* card_copy = card->CreateCopy();
				return card_copy;
			}
		}
	| randomCard: int cost
		{
			generator { cost = GetRandInt(0, 10); }
			FillRep
			{
				rep.push_back(mkNodeRep(4, <double>{NormalizeCode(cost, 0, 10)}));
			}
			Detail = "a random cost " + IntToStr(cost) + " card";
			DetailAlt1 = "random cost " + IntToStr(cost) + " cards";
			CreateNodeHardCopy = new randomCard(card_copy, cost);
			GetTargetConfig = HAND_OR_DECK_COND_FILTER;
			GetRelatedCard = CreateRandomCard(parent_card->name, cost, 0, parent_card->max_eff_num, 0); 
		}
	| randomMinion: int cost
		{
			generator { cost = GetRandInt(0, 10); }
			FillRep
			{
				rep.push_back(mkNodeRep(5, <double>{NormalizeCode(cost, 0, 10)}));
			}
			Detail = "a random cost " + IntToStr(cost) + " minion";
			DetailAlt1 = "random cost " + IntToStr(cost) + " minions"; // for plural
			CreateNodeHardCopy = new randomMinion(card_copy, cost);
			GetTargetConfig = MINION_COND_FILTER & FIELD_COND_FILTER;
			GetRelatedCard 
			{
				Card* card = CreateRandomMinion(parent_card->name, cost, 0, parent_card->max_eff_num, 0); 
				return card;
			}
		}

};

giglconfig GetDefaultGenConfig(int seed)
{
	return <* Card{#seed, 3, 2}: // after separated the config, it is important to add # to the local (non-reference) variables at configuration time, as local addresses are not preserved
		CardRoot := leaderCard @ {0.1} | minionCard @ {0.6} | spellCard @ {0.3},
		AttackTimes := zeroAttack @ {0.02} | singleAttack | multipleAttack @ {0.08},
		MinionType := beastMinion | dragonMinion | demonMinion,
		Attributes := justAttributes,
		DamageAttributes := damageAttributes,
		ChargeAttr := noCharge | justCharge @ {0.05},
		TauntAttr := noTaunt | justTaunt @ {0.05},
		StealthAttr := noStealth | justStealth @ {0.05},
		UntargetableAttr := noUntargetable | justUntargetable @ {0.05},
		ShieldAttr := noShield | justShield @ {0.05},
		PoisonousAttr := noPoisonous | justPoisonous @ {0.01*(10 - damage)},
		LifestealAttr := noLifesteal | justLifesteal @ {damage == 0 ? 0.01 : 0.05},
		SpecialEffects := specialEffects,
		TargetedPlayEff := noTargetedPlayEff | targetedBattlecryEff @ {0.15} | targetedCastEff @ {0.30},
		OtherEffs := noOtherEffs | consOtherEffs @ {-1.0 / (min_n - 2)}, // note min_n can be at most 1 and will be come smaller (more negative) as it goes deeper
		OtherEff := untargetedBattlecryEff @ {30} | untargetedCastEff @ {475} | deathrattleEff @ {45} | onDiscardEff @ {5} | turnStartEff @ {10} | turnEndEff @ {10},
		TargetedEff := noCondTargetedEff | indeCondTargetedEff @ {0.1} | srcCondTargetedEff @ {0.05},
		UntargetedEff := noCondUntargetedEff | indeCondUntargetedEff @ {0.1} | srcCondUntargetedEff @ {0.05},
		TargetCond := charTargetCond @ {0.8} | cardTargetCond @ {0.2},
		CharTargetCond := justCharTargetCond,
		CharTypeCond := isCharacter @ {0.30} | isMinion @ {0.55} | isBeast | isDragon | isDemon,
		CardTargetCond := justCardTargetCond,
		CardTypeCond := isCard @ {0.5} | isLeaderCard @ {0.03} | isMinionCard @ {0.15} | isSpellCard @ {0.12} | isBeastCard | isDragonCard | isDemonCard,
		CardPosCond := cardPosAtHandOrDeck @ {0.1} | cardPosAtHand @ {0.7} | cardPosAtDeck,
		AllegianceCond := anyAllegiance @ {0.3} | allyAllegiance | oppoAllegiance,
		AttrCond := noAttrCond @ {950} | chargeCond @ {10} | tauntCond @ {10} | stealthCond @ {8} | untargetableCond @ {7} | shieldCond @ {5} | poisonousCond @ {5} | lifestealCond @ {5},
		StatCond := noStatCond @ {900} | costCond @ {30} | atkCond @ {30} | hpCond @ {30} | atkTimesCond @ {10}, 
		StatCondVariant := statGe | statLe,
		IndeCond := fieldExistenceCond @ {0.4} | cardExistenceCond @ {0.2} | leaderCond @ {0.2} | mpCond @ {0.1} | maxMpCond @ {0.1},
		BaseTargetedEff := damageEff @ {400} | healEff @ {180} | resAtkTimesEff @ {15} | costModEff{0.2} @ {70} | atkHpModEff @ {70} | atkTimesModEff{0.2} @ {10} | destroyEff @ {80} | discardEff @ {20} | moveEff @ {50} | copyEff @ {50} | transformEff @ {20.0/(1 + effect_depth)}
			| changeToBeastEff @ {10} | changeToDragonEff @ {10} | changeToDemonEff @ {10} | giveChargeEff @ {10} | giveTauntEff @ {10} | giveStealthEff @ {10} | giveUntargetableEff @ {10} | giveShieldEff @ {10} | givePoisonousEff @ {10} | giveLifestealEff @ {10}
			| rmAttributesEff @ {20} | setOverheatEff @ {10} | decOhThresholdEff @ {10} | resetStateEff @ {10} | giveEffectsEff @ {20.0/(1 + effect_depth)},
		BaseUntargetedEff := aoeEff @ {500} | randEff @ {250} | leaderEff @ {150} | selfEff @ {30} | drawCardEff @ {50} | mpEff{0.2} @ {10} | maxMpEff{0.3} @ {10} | newEff @ {30} | winGameEff @ {1},
		Destination := fieldDest @ {10} | ownerFieldDest @ {15} | handDest @ {20} | ownerHandDest @ {40} | deckDest @ {5} | ownerDeckDest @ {10},
		NewCardVariant := plainMinionCard @ {20} | plainMinion @ {50} | fixedCard @ {5} | fixedMinion @ {15} | randomCard @ {3} | randomMinion @ {7},
		*>;
}

Card* GenerateCard(int seed)
{
	RandInit(seed);
	return generate Card with GetDefaultGenConfig(seed);
}

Card* CreateDefaultLeader(int hp)
{
	Card* leader = construct Card(leaderCard(7, 0, hp, singleAttack(), justAttributes(noCharge(), noTaunt(), noStealth(), noUntargetable(), noShield(), noPoisonous(), noLifesteal()), specialEffects(noTargetedPlayEff(), noOtherEffs()))) with GetDefaultGenConfig(GetRandInt());
	leader->name = "Default Leader";
	return leader;
}

Card* CreateSndPlayerToken()
{
	Card* token = construct Card(spellCard(0, justAttributes(noCharge(), noTaunt(), noStealth(), noUntargetable(), noShield(), noPoisonous(), noLifesteal()),
						specialEffects(targetedCastEff(noCondTargetedEff(costModEff(-1), cardTargetCond(justCardTargetCond(cardPosAtHand(), allyAllegiance(), isCard(), noAttrCond(), noStatCond())))),
							consOtherEffs(untargetedCastEff(noCondUntargetedEff(drawCardEff(1, allyAllegiance()))),
								noOtherEffs())))) with GetDefaultGenConfig(GetRandInt());
	token->name = "Second Player Token";
	return token;
}

Card* CreatePlainMinion(string parent_name)
{
	int seed = GetRandInt();
	RandInit(seed);
	CondConfig tmp_config = GetFlagConfig(MINION_COND_FILTER); // to get around the issue of rvalue passed to lvalue ref
	Card* card = construct Card(generate CardRoot(tmp_config, true)) with GetDefaultGenConfig(seed);
	card->name = parent_name + "_Spawn_#" + IntToStr(seed);
	
	return card;
}

Card* CreateRandomMinion(string parent_name, int cost, int min_eff_num, int max_eff_num, int eff_depth)
{
	// this uses a two step process because current implementation item constructor in GIGL relies on lifting decls to global scope, therefore any generation recursive on the item level will overwrite the global lifted variable in the middle of the process and messing it up
	int seed = GetRandInt();
	RandInit(seed);
	CondConfig tmp_config = GetCostConfig(MINION_COND_FILTER, cost, cost); // to get around the issue of rvalue passed to lvalue ref
	Card* card = construct Card(generate CardRoot(tmp_config, true)) with GetDefaultGenConfig(seed);
	card->name = parent_name + "_Spawn_#" + IntToStr(seed);
	card->Mutate(min_eff_num, max_eff_num, eff_depth);

	return card;
}

Card* CreateRandomCard(string parent_name, int cost, int min_eff_num, int max_eff_num, int eff_depth)
{
	// this uses a two step process because current implementation item constructor in GIGL relies on lifting decls to global scope, therefore any generation recursive on the item level will overwrite the global lifted variable in the middle of the process and messing it up
	int seed = GetRandInt();
	RandInit(seed);
	CondConfig tmp_config = GetCostConfig(TARGET_TYPE_ANY, cost, cost); // to get around the issue of rvalue passed to lvalue ref
	Card* card = construct Card(generate CardRoot(tmp_config, true)) with GetDefaultGenConfig(seed);
	card->name = parent_name + "_Spawn_#" + IntToStr(seed);
	card->Mutate(min_eff_num, max_eff_num, eff_depth);

	return card;
}
