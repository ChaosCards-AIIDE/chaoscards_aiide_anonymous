#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <numeric>
#include <algorithm>
#include <functional>
#include <ctime>

#include "Player.h"

using namespace std;

string Match_Card_Data_Path_Raw = "match_card_data_raw.txt";
string Match_Card_Data_Path_Processed = "match_card_data_processed.txt";
string Match_Card_Data_Path_Human = "match_card_data_human.txt";
string Card_Model_Path = "card_model.pt";
string Card_Train_Log_Path = "card_model_train_log.txt";
string Card_Train_Correlation_Path = "train_correlation.txt";
string Card_Validate_Correlation_Path = "validate_correlation.txt";

struct MatchStat // can be for a deck or a card
{
	MatchStat() : num_wins(0), num_losses(0), total_num(0), win_contribution(0.0), total_participation(0.0), eval(0.5) {}
	void WinUpdate(double participation) 
	{
		num_wins++;
		total_num++;
		win_contribution += participation * 1.0;
		total_participation += participation;
		
	}
	void LoseUpdate(double participation)
	{
		num_losses++;
		total_num++;
		total_participation += participation;	
	}
	void DrawUpdate(double participation)
	{
		total_num++;
		win_contribution += participation * 0.5;
		total_participation += participation;
	}
	void UpdateEval() 
	{
		if (total_participation > 0)
			eval = win_contribution / total_participation;
	}
	int num_wins;
	int num_losses;
	int total_num;
	double win_contribution;
	double total_participation;
	double eval;
};

void UpdateStatEvals(vector<MatchStat>& stats)
{
	for (auto& stat: stats) // note the & is very important otherwise it won't update the original copies
		stat.UpdateEval();
}

bool StatIndexComparator(const vector<MatchStat>& stats, int i, int j)
{
	return stats[i].eval > stats[j].eval;
}

void SortStatInIndices(const vector<MatchStat>& stats, vector<int>& indices)
{
	iota(indices.begin(), indices.end(), 0); // fill index with {0,1,2,...}
	sort(indices.begin(), indices.end(), bind(StatIndexComparator, stats, placeholders::_1, placeholders::_2)); 
}


void CountCardsInSingleDeck(const vector<int>& deck, vector<int>& counts)
{
	for (int c_index: deck)
		counts[c_index]++;
}

void CountCardsInDecks(const vector<vector<int>>& decks, vector<int>& counts)
{
	for (const auto& deck: decks)
		CountCardsInSingleDeck(deck, counts); 
}

void ReplaceCardInSingleDeck(vector<int>& deck, int search_for_index, int replace_with_index)
{
	for (int& c_index: deck)
		if (c_index == search_for_index)
			c_index = replace_with_index;
}

void ReplaceCardInDecks(vector<vector<int>>& decks, int search_for_index, int replace_with_index)
{
	for (auto& deck: decks)
		ReplaceCardInSingleDeck(deck, search_for_index, replace_with_index);
}

void ReplaceSignificantCardInDeckPool(vector<vector<int>>& decks, int& selected_index, int new_index, int card_pool_size) // will select a single card randomly among cards with significant appearance in the decks to replace
{
	vector<int> card_appearance_count(card_pool_size, 0);
	CountCardsInDecks(decks, card_appearance_count);
	
	// threshold #1: should at least appear with average count (rounding up; it always exist because of pigeonhold principle)
	int deck_num = decks.size();
	int deck_size = decks[0].size();
	int ave_count_threshold = (deck_size * deck_num  - 1) / card_pool_size + 1; // the -1 and +1 is simulating celling effect
	
	// threshold #2: should at least appear with half of the max count (rounding up)
	int max_count = 0;
	for (int i = 0; i < card_pool_size; i++)
		if (card_appearance_count[i] > max_count)
			max_count = card_appearance_count[i];
	int half_max_threshold = (max_count - 1) / 2 + 1; // the -1 and +1 is simulating celling effect

	// randomly select among candidates
	vector<int> candidates;
	for (int i = 0; i < card_pool_size; i++)
		if (card_appearance_count[i] >= ave_count_threshold && card_appearance_count[i] >= half_max_threshold)
			candidates.push_back(i);
	int selected_candidate_index = GetGiglRandInt(candidates.size());
	
	ReplaceCardInDecks(decks, selected_index, new_index);
}

void TestAIs(int ai_level_a, int ai_level_b, const vector<int>& seed_list, const vector<vector<int>>& deck_list, int deck_num, int deck_size) // deck_list stores indices in the seed_list, not the seeds themselves
{
	MatchStat ai_stat_a, ai_stat_b;
	for (int i = 0; i < deck_num; i++)
	{
		for (int j = 0; j < deck_num; j++)
		{
			cout << "AI_A Deck " << i << " VS AI_B Deck " << j << ". ";

			vector<int> deck_a_indices = deck_list[i]; // make a copy so that if needed it is easier to reproduce with shuffling from the original order
			vector<int> deck_b_indices = deck_list[j]; // make a copy so that if needed it is easier to reproduce with shuffling from the original order
			vector<int> deck_a_seeds(deck_size);
			vector<int> deck_b_seeds(deck_size);

			InitMatch(seed_list, deck_a_indices, deck_b_indices, deck_a_seeds, deck_b_seeds);			

			vector<Card*> deck_a = GenerateRandDeckFromSeedList(deck_a_seeds);
			vector<Card*> deck_b = GenerateRandDeckFromSeedList(deck_b_seeds);

			queue<DeferredEvent*> event_queue;
			Player player1("AI_A", 30, deck_a, true, event_queue, ai_level_a);
			Player player2("AI_B", 30, deck_b, true, event_queue, ai_level_b);

			player1.opponent = &player2;
			player2.opponent = &player1;

			player1.SetAllCardAfflications();
			player2.SetAllCardAfflications();

			player1.InitialCardDraw(false);
			player2.InitialCardDraw(true);

			while (true)
			{
				player1.StartTurn();
				(player1.*(player1.input_func))();
				if (player1.CheckLose() || player2.CheckLose())
					break;

				player2.StartTurn();
				(player2.*(player2.input_func))();
				if (player1.CheckLose() || player2.CheckLose())
					break;
			}

			while (!event_queue.empty())
			{
				delete event_queue.front(); // note: this is not deleting the actual card but the entity for flagging
				event_queue.pop();
			}

			if (player1.CheckLose())
			{
				if (player2.CheckLose())
				{
					// draw
					ai_stat_a.DrawUpdate(1.0);
					ai_stat_b.DrawUpdate(1.0);
					cout << "They drew." << endl;
				}
				else
				{
					// AI_A loses, deck AI_B wins
					ai_stat_a.LoseUpdate(1.0);
					ai_stat_b.WinUpdate(1.0);
					cout << "AI_B won." << endl;
				}
			}
			else
			{
				// AI_A wins, deck AI_B loses
				ai_stat_a.WinUpdate(1.0);
				ai_stat_b.LoseUpdate(1.0);
				cout << "AI_A won." << endl;
			}

		}
	}

	ai_stat_a.UpdateEval();
	cout << "AI_A level: " << ai_level_a << endl;
	cout << "AI_A total matches: " << ai_stat_a.total_num << endl;
	cout << "AI_A wins: " << ai_stat_a.num_wins << endl;
	cout << "AI_A losses: " << ai_stat_a.num_losses << endl;
	cout << "AI_A eval: " << ai_stat_a.eval << endl;
	ai_stat_b.UpdateEval();
	cout << "AI_B level: " << ai_level_b << endl;
	cout << "AI_B total matches: " << ai_stat_b.total_num << endl;
	cout << "AI_B wins: " << ai_stat_b.num_wins << endl;
	cout << "AI_B losses: " << ai_stat_b.num_losses << endl;
	cout << "AI_B eval: " << ai_stat_b.eval << endl;
}

int SimulateSingleMatchBetweenDecks(int ai_level, const vector<int>& seed_list, const vector<int>& deck_a_orig_indices, const vector<int>& deck_b_orig_indices, vector<MatchStat>& card_stats, MatchStat& deck_a_stat, MatchStat& deck_b_stat, int deck_size) // return number of turns when the match ends, both sides summed
{
	vector<int> deck_a_indices = deck_a_orig_indices; // make a copy so that if needed it is easier to reproduce with shuffling from the original order
	vector<int> deck_b_indices = deck_b_orig_indices; // make a copy so that if needed it is easier to reproduce with shuffling from the original order
	vector<int> deck_a_seeds(deck_size);
	vector<int> deck_b_seeds(deck_size);

	InitMatch(seed_list, deck_a_indices, deck_b_indices, deck_a_seeds, deck_b_seeds);

	vector<Card*> deck_a = GenerateRandDeckFromSeedList(deck_a_seeds);
	vector<Card*> deck_b = GenerateRandDeckFromSeedList(deck_b_seeds);

	queue<DeferredEvent*> event_queue;
	Player player1("AI_Deck_A", 30, deck_a, true, event_queue, ai_level);
	Player player2("AI_Deck_B", 30, deck_b, true, event_queue, ai_level);

	vector<int> contribution_counters_a(deck_size, 0);
	player1.RegisterCardContributions(contribution_counters_a);
	vector<int> contribution_counters_b(deck_size, 0);
	player2.RegisterCardContributions(contribution_counters_b);

	player1.opponent = &player2;
	player2.opponent = &player1;

	player1.SetAllCardAfflications();
	player2.SetAllCardAfflications();

	player1.InitialCardDraw(false);
	player2.InitialCardDraw(true);

	while (true)
	{
		player1.StartTurn();
		(player1.*(player1.input_func))();
		if (player1.CheckLose() || player2.CheckLose())
			break;

		player2.StartTurn();
		(player2.*(player2.input_func))();
		if (player1.CheckLose() || player2.CheckLose())
			break;
	}

	while (!event_queue.empty())
	{
		delete event_queue.front(); // note: this is not deleting the actual card but the entity for flagging
		event_queue.pop();
	}

	int sum_contribution_a = 0;
	for (int k = 0; k < deck_size; k++)
		sum_contribution_a += contribution_counters_a[k];
	int sum_contribution_b = 0;
	for (int k = 0; k < deck_size; k++)
		sum_contribution_b += contribution_counters_b[k];

	if (player1.CheckLose())
	{
		if (player2.CheckLose())
		{
			// draw
			deck_a_stat.DrawUpdate(1.0);
			deck_b_stat.DrawUpdate(1.0);
			for (int k = 0; k < deck_size; k++)
			{
				card_stats[deck_a_indices[k]].DrawUpdate(contribution_counters_a[k] / (double)sum_contribution_a);
				card_stats[deck_b_indices[k]].DrawUpdate(contribution_counters_b[k] / (double)sum_contribution_b);
			}
			cout << "They drew." << endl;
		}
		else
		{
			// deck i loses, deck j wins
			deck_a_stat.LoseUpdate(1.0);
			deck_b_stat.WinUpdate(1.0);
			for (int k = 0; k < deck_size; k++)
			{
				card_stats[deck_a_indices[k]].LoseUpdate(contribution_counters_a[k] / (double)sum_contribution_a);
				card_stats[deck_b_indices[k]].WinUpdate(contribution_counters_b[k] / (double)sum_contribution_b);
			}
			cout << "The second deck won." << endl;
		}
	}
	else
	{
		// deck i wins, deck j loses
		deck_a_stat.WinUpdate(1.0);
		deck_b_stat.LoseUpdate(1.0);
		for (int k = 0; k < deck_size; k++)
		{
			card_stats[deck_a_indices[k]].WinUpdate(contribution_counters_a[k] / (double)sum_contribution_a);
			card_stats[deck_b_indices[k]].LoseUpdate(contribution_counters_b[k] / (double)sum_contribution_b);
		}
		cout << "The first deck won." << endl;
	}

	return player1.turn_num + player2.turn_num;
}

int SimulatePairMatchBetweenDecks(int ai_level, const vector<int>& seed_list, const vector<int>& deck_a_orig_indices, const vector<int>& deck_b_orig_indices, vector<MatchStat>& card_stats, MatchStat& deck_a_stat, MatchStat& deck_b_stat, int deck_size) // return total number of match turns (both sides summed)
{
	// test both the playing order (which player plays first and with plays second)
	int turn_count_1 = SimulateSingleMatchBetweenDecks(ai_level, seed_list, deck_a_orig_indices, deck_b_orig_indices, card_stats, deck_a_stat, deck_b_stat, deck_size);
	int turn_count_2 = SimulateSingleMatchBetweenDecks(ai_level, seed_list, deck_b_orig_indices, deck_a_orig_indices, card_stats, deck_b_stat, deck_a_stat, deck_size);
	return turn_count_1 + turn_count_2;
}

int TestNewDeck(int ai_level, const vector<int>& seed_list, vector<vector<int>>& deck_list, vector<MatchStat>& card_stats, vector<MatchStat>& deck_stats, int deck_size, double temperature, int num_pair_matches, int& deck_count, int& match_pair_count) // return total number of match turns (both sides summed)
{
	int p = seed_list.size();
	int n_decks = deck_list.size();
	
	/* creating the new deck*/
	vector<int> new_deck(deck_size);
	double two_ln_visits = 2.0 * log(4.0 * match_pair_count * deck_size); // the natural logarithm of total number of times any card is tested so far
	vector<double> weights(p);
	vector<int> unvisited_indices;
	for (int i = 0; i < p; i++)
	{
		int tmp_visits = card_stats[i].total_num;
		if (tmp_visits == 0) // not tested at all, mark as -1
			unvisited_indices.push_back(i);
		else
			weights[i] = card_stats[i].eval + sqrt(two_ln_visits/(double)tmp_visits);
	}

	int n_unvisited = unvisited_indices.size();
	if (n_unvisited >= deck_size) // if there are enough unvisited ones, choose among them
	{
		vector<int> selected_unvisited_indices = CreateRandomSelection(n_unvisited, deck_size);
		for (int i = 0; i < deck_size; i++)
			new_deck[i] = unvisited_indices[selected_unvisited_indices[i]];
		sort(new_deck.begin(), new_deck.end());	
	}
	else // otherwise first choose all unvisited ones, then choose the remaining with max UCB weights
	{
		for (int i = 0; i < n_unvisited; i++)
		{
			int tmp_index = unvisited_indices[i];
			new_deck[i] = tmp_index;
			weights[tmp_index] = -10.0; // mark as already selected
		}
		for (int i = n_unvisited; i < deck_size; i++)
		{
			double max_weight = -10.0;
			double selected_card_index = -1; // will be overwritten
			for (int j = 0; j < p; j++)
				if (weights[j] > max_weight)
				{
					max_weight = weights[j];
					selected_card_index = j;
				}
			new_deck[i] = selected_card_index;
			weights[selected_card_index] = -10.0; // mark as already selected
		}
		sort(new_deck.begin(), new_deck.end());
	}

	/* check if the mutated deck is a duplicate of any existing deck */
	int duplicate_index = -1;
	for (int i = 0; i < n_decks; i++)
		if (new_deck == deck_list[i]) // comparing two vector of ints; as they are expected to be sorted so that makes sense here
		{
			duplicate_index = i;
			break;	
		}

	/* perform tests, update the deck pool if necessary */
	int turn_count = 0;
	if (duplicate_index >= 0) // if it is a duplicate, just re-test
	{
		for (int i = 0; i < n_decks; i++)
			if (i != duplicate_index)
				for (int k = 0; k < num_pair_matches; k++) 
				{
					cout << "Match Pair #" << ++match_pair_count << endl;
					turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_list[duplicate_index], card_stats, deck_stats[i], deck_stats[duplicate_index], deck_size);
				}		
		UpdateStatEvals(deck_stats);
	}
	else // if it is not a duplicate, test and decide whether to replace the worst among other decks
	{
		deck_count++;
		MatchStat tmp_deck_stat;
		for (int i = 0; i < n_decks; i++)
			for (int k = 0; k < num_pair_matches; k++) 
			{
				cout << "Match Pair #" << ++match_pair_count << endl;
				turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], new_deck, card_stats, deck_stats[i], tmp_deck_stat, deck_size);
			}
		UpdateStatEvals(deck_stats);
		tmp_deck_stat.UpdateEval();

		// find the worst among other decks
		double min_eval = 10.0;
		int min_index = -1; // this should always be overwritten
		for (int i = 0; i < n_decks; i++)
			if (deck_stats[i].eval < min_eval)
			{
				min_eval = deck_stats[i].eval;
				min_index = i;
			}	
		
		// use Metropolis-MC like rejection scheme to decide whether to accept the replacement or not
		double accept_prob = exp((tmp_deck_stat.eval - min_eval)/temperature);
		double roll = GetGiglRandFloat();
		if (roll < accept_prob) // accept and replace, otherwise don't do the replacement
		{
			deck_list[min_index] = new_deck;
			deck_stats[min_index] = tmp_deck_stat;
			cout << "Update accepted." << endl;
		}
		else
		{
			cout << "Update rejected." << endl;
		}
	}

	return turn_count;
}

int TestCrossOver(int ai_level, const vector<int>& seed_list, vector<vector<int>>& deck_list, vector<MatchStat>& card_stats, vector<MatchStat>& deck_stats, int deck_size, double temperature, int num_pair_matches, int& deck_count, int& match_pair_count) // return total number of match turns (both sides summed)
{
	int n_decks = deck_list.size();

	/* creating the cross over offsprings (two) */
	vector<int> selected_deck_indices = CreateRandomSelection(n_decks, 2);
	vector<vector<int>> deck_copies(2);
	for (int i = 0; i < 2; i++)
		deck_copies[i] = deck_list[selected_deck_indices[i]];

	// first figure out cards not shared by the two decks, then decide which ones to swap
	int i0 = 0, i1 = 0;
	vector<int> diff_indices0, diff_indices1;
	while (i0 < deck_size && i1 < deck_size)
	{
		if (deck_copies[0][i0] == deck_copies[1][i1])
		{
			i0++;
			i1++;
		}
		else if (deck_copies[0][i0] < deck_copies[1][i1])
		{
			do
			{
				diff_indices0.push_back(i0);
				i0++;
			}
			while (i0 < deck_size && deck_copies[0][i0] < deck_copies[1][i1]);
		}
		else
		{
			do
			{
				diff_indices1.push_back(i1);
				i1++;
			}
			while (i1 < deck_size && deck_copies[0][i0] > deck_copies[1][i1]);
		}
	}
	// don't forget the remaining unmatched indices
	for (; i0 < deck_size; i0++)
		diff_indices0.push_back(i0);
	for (; i1 < deck_size; i1++)
		diff_indices1.push_back(i1);
	int diff_size = diff_indices0.size(); // should be the same for 0 and 1
	vector<int> index_map = CreateRandomSelection(diff_size, diff_size); // essentially a random shuffle on indices
	for (int i = 0; i < diff_size; i++)
	{
		double roll = GetGiglRandFloat();
		if (roll < 0.5) // 50% chance to swap (if nothing ends up swapping we'll just test the two decks again at the end, not a problem)
		{
			int i0 = diff_indices0[i];
			int i1 = diff_indices1[index_map[i]];
			int tmp = deck_copies[0][i0];
			deck_copies[0][i0] = deck_copies[1][i1];
			deck_copies[1][i1] = tmp;
		}
	}
	for (int i = 0; i < 2; i++)
		sort(deck_copies[i].begin(), deck_copies[i].end());	
	
	/* check duplicates */
	vector<int> duplicate_indices(2, -1);
	for (int i = 0; i < 2; i++)
	{
		for (int j = 0; j < n_decks; j++)
			if (deck_copies[i] == deck_list[j]) // comparing two vector of ints; as they are expected to be sorted so that makes sense here
			{
				duplicate_indices[i] = j;
				break;	
			}
	}
	
	/* perform tests */
	int turn_count = 0;
	vector<MatchStat> tmp_deck_stats(2);
	for (int i = 0; i < 2; i++)
	{
		if (duplicate_indices[i] >= 0) // if it is a duplicate
		{
			for (int j = 0; j < n_decks; j++)
				if (j != duplicate_indices[i])
					for (int k = 0; k < num_pair_matches; k++) 
					{
						cout << "Match Pair #" << ++match_pair_count << endl;
						turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[j], deck_list[duplicate_indices[i]], card_stats, deck_stats[j], deck_stats[duplicate_indices[i]], deck_size);
					}		
			UpdateStatEvals(deck_stats);
		}
		else // if it is not a duplicate
		{
			deck_count++;
			for (int j = 0; j < n_decks; j++)
				for (int k = 0; k < num_pair_matches; k++) 
				{
					cout << "Match Pair #" << ++match_pair_count << endl;
					turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[j], deck_copies[i], card_stats, deck_stats[j], tmp_deck_stats[i], deck_size);
				}
			UpdateStatEvals(deck_stats);
			tmp_deck_stats[i].UpdateEval();
		}	
	}
	// if both are not duplicates, do a set of matches between them
	if (duplicate_indices[0] < 0 && duplicate_indices[1] < 0)
	{
		for (int k = 0; k < num_pair_matches; k++)
		{
			cout << "Match Pair #" << ++match_pair_count << endl;
			turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_copies[0], deck_copies[1], card_stats, tmp_deck_stats[0], tmp_deck_stats[1], deck_size);
		}
		tmp_deck_stats[0].UpdateEval();
		tmp_deck_stats[1].UpdateEval();
	}

	/* update the deck pool if necessary */
	// replacement logic:
	// if both offsprings are duplicates, no replacement needed
	// if one offspring is a duplicate, decide whether to replace the weaker of the two parents or not
	// if none of them is a duplicate, decide whether to replace both parents or not
	if (duplicate_indices[0] < 0)
	{
		if (duplicate_indices[1] < 0) // both decks are new
		{
			// use Metropolis-MC like rejection scheme to decide whether to accept the replacement or not
			double accept_prob = exp(((tmp_deck_stats[0].eval + tmp_deck_stats[1].eval) - (deck_stats[selected_deck_indices[0]].eval + deck_stats[selected_deck_indices[1]].eval))/temperature);
			double roll = GetGiglRandFloat();
			if (roll < accept_prob) // accept and replace, otherwise don't do the replacement
			{
				for (int i = 0; i < 2; i++)
				{
					deck_list[selected_deck_indices[i]] = deck_copies[i];
					deck_stats[selected_deck_indices[i]] = tmp_deck_stats[i];
				}
				cout << "Update accepted." << endl;
			}
			else
			{
				cout << "Update rejected." << endl;
			}
		}
		else // only the first deck is new
		{
			// first figure out the weaker of the two parents
			int replace_target = (deck_stats[selected_deck_indices[0]].eval <= deck_stats[selected_deck_indices[1]].eval ? selected_deck_indices[0] : selected_deck_indices[1]);
			// use Metropolis-MC like rejection scheme to decide whether to accept the replacement or not
			double accept_prob = exp((tmp_deck_stats[0].eval - deck_stats[replace_target].eval)/temperature);
			double roll = GetGiglRandFloat();
			if (roll < accept_prob) // accept and replace, otherwise don't do the replacement
			{
				deck_list[replace_target] = deck_copies[0];
				deck_stats[replace_target] = tmp_deck_stats[0];
				cout << "Update accepted." << endl;
			}
			else
			{
				cout << "Update rejected." << endl;
			}
		}
	}
	else
	{
		if (duplicate_indices[1] < 0) // only the second deck is new
		{
			// first figure out the weaker of the two parents
			int replace_target = (deck_stats[selected_deck_indices[0]].eval <= deck_stats[selected_deck_indices[1]].eval ? selected_deck_indices[0] : selected_deck_indices[1]);
			// use Metropolis-MC like rejection scheme to decide whether to accept the replacement or not
			double accept_prob = exp((tmp_deck_stats[1].eval - deck_stats[replace_target].eval)/temperature);
			double roll = GetGiglRandFloat();
			if (roll < accept_prob) // accept and replace, otherwise don't do the replacement
			{
				deck_list[replace_target] = deck_copies[1];
				deck_stats[replace_target] = tmp_deck_stats[1];
				cout << "Update accepted." << endl;
			}
			else
			{
				cout << "Update rejected." << endl;
			}
		}
		// else do nothing
	}

	return turn_count;
}

int TestMutation(int ai_level, const vector<int>& seed_list, vector<vector<int>>& deck_list, vector<MatchStat>& card_stats, vector<MatchStat>& deck_stats, int deck_size, double temperature, int num_pair_matches, int deck_count, int& match_pair_count) // return total number of match turns (both sides summed)
{
	int p = seed_list.size();
	int n_decks = deck_list.size();

	/* creating the mutated deck*/	
	int selected_deck_index = GetGiglRandInt(n_decks);
	vector<int> deck_copy = deck_list[selected_deck_index];
	double two_ln_visits = 2.0 * log(4.0 * match_pair_count * deck_size); // the natural logarithm of total number of times any card is tested so far
	vector<double> weights(p);
	vector<int> unvisited_indices;
	for (int i = 0; i < p; i++)
	{
		int tmp_visits = card_stats[i].total_num;
		if (tmp_visits == 0) // not tested at all, mark as -1
			unvisited_indices.push_back(i); // we can decide here (instead of needing to wait for checking/clearing for cards in the selected deck) because any cards in the existing decks should all be already tested
		else
			weights[i] = card_stats[i].eval + sqrt(two_ln_visits/(double)tmp_visits);
	}
	
	int selected_card_index;
	int n_unvisited = unvisited_indices.size();
	if (n_unvisited > 0) // there are unvisited cards: get one randomly from them
	{
		selected_card_index = unvisited_indices[GetGiglRandInt(n_unvisited)];
	}
	else // no unvisited cards: select one with max UCB weight (but not any card from the selected deck to mutate from)
	{
		for (int i = 0; i < deck_size; i++) // clearing the weights of any cards in the selected deck because we don't want duplicate or identity mutation
			weights[deck_copy[i]] = -10.0;  // using the copied deck as the original as it shouldn't have been modified up to this point
		double max_weight = -10.0;
		selected_card_index = -1; // will be overwritten
		for (int i = 0; i < p; i++)
			if (weights[i] > max_weight)
			{
				max_weight = weights[i];
				selected_card_index = i;
			}
	}
	
	int replaced_index_in_deck = GetGiglRandInt(deck_size);
	deck_copy[replaced_index_in_deck] = selected_card_index;
	// keep the card index in the deck sorted (increasing)
	int k = replaced_index_in_deck; 
	while(k > 0 && deck_copy[k] < deck_copy[k - 1])
	{
		int tmp = deck_copy[k];
		deck_copy[k] = deck_copy[k - 1];
		deck_copy[k - 1] = tmp;
		k--;
	}
	while(k < deck_size - 1 && deck_copy[k] > deck_copy[k + 1])
	{
		int tmp = deck_copy[k];
		deck_copy[k] = deck_copy[k + 1];
		deck_copy[k + 1] = tmp;
		k++;
	}

	/* check if the mutated deck is a duplicate of any existing deck */
	int duplicate_index = -1;
	for (int i = 0; i < n_decks; i++)
		if (deck_copy == deck_list[i]) // comparing two vector of ints; as they are expected to be sorted so that makes sense here
		{
			duplicate_index = i;
			break;	
		}

	/* perform tests, update the deck pool if necessary */
	int turn_count = 0;
	if (duplicate_index >= 0) // if it is a duplicate, just re-test
	{
		for (int i = 0; i < n_decks; i++)
			if (i != duplicate_index)
				for (int k = 0; k < num_pair_matches; k++) 
				{
					cout << "Match Pair #" << ++match_pair_count << endl;
					turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_list[duplicate_index], card_stats, deck_stats[i], deck_stats[duplicate_index], deck_size);
				}		
		UpdateStatEvals(deck_stats);
	}
	else // if it is not a duplicate, test and decide whether to replace the original deck it mutates from
	{
		deck_count++;
		MatchStat tmp_deck_stat;
		for (int i = 0; i < n_decks; i++)
			for (int k = 0; k < num_pair_matches; k++) 		
			{
				cout << "Match Pair #" << ++match_pair_count << endl;
				turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_copy, card_stats, deck_stats[i], tmp_deck_stat, deck_size);
			}
		UpdateStatEvals(deck_stats);
		tmp_deck_stat.UpdateEval();
		
		// use Metropolis-MC like rejection scheme to decide whether to accept the replacement or not
		double accept_prob = exp((tmp_deck_stat.eval - deck_stats[selected_deck_index].eval)/temperature);
		double roll = GetGiglRandFloat();
		if (roll < accept_prob) // accept and replace, otherwise don't do the replacement
		{
			deck_list[selected_deck_index] = deck_copy;
			deck_stats[selected_deck_index] = tmp_deck_stat;
			cout << "Update accepted." << endl;
		}
		else
		{
			cout << "Update rejected." << endl;
		}
	}

	return turn_count;
}


void WriteRawData(const vector<int>& card_seeds, const vector<MatchStat>& card_stats, const char* filename = Match_Card_Data_Path_Raw.c_str())
{
	int p = card_seeds.size();

	ofstream fs(filename);
	fs << p << endl;
	for (int i = 0; i < p; i++)
		fs << card_seeds[i] << " " << card_stats[i].eval << " "
			<< card_stats[i].num_wins << " " << card_stats[i].num_losses << " " << card_stats[i].total_num << " "
			<< card_stats[i].win_contribution << " " << card_stats[i].total_participation << endl;
	fs.close();
	fs.clear();
}

void WriteSingleCardData(const CardRep& card_rep, double card_strength, ofstream& fs)
{
	int tmp_rep_len = card_rep.size();
	fs << tmp_rep_len << ":: ";
	for (int j = 0; j < tmp_rep_len; j++)
		fs << card_rep[j].GetPrintVersion();
	fs << card_strength << endl;
}

void WriteData(const vector<CardRep>& card_reps, const vector<double>& card_strengths, const char* filename = Match_Card_Data_Path_Processed.c_str())
{
	int p = card_reps.size();

	ofstream fs(filename);
	fs << p << endl;
	for (int i = 0; i < p; i++)
		WriteSingleCardData(card_reps[i], card_strengths[i], fs);
	fs.close();
	fs.clear();
}

void WriteDataHuman(const vector<int>& card_seeds, const vector<CardRep>& card_reps, const vector<double>& card_strengths, const char* filename = Match_Card_Data_Path_Human.c_str()) // more human readable verion, with card info
{
	int p = card_reps.size();

	ofstream fs(filename);
	fs << p << endl << endl;
	for (int i = 0; i < p; i++)
	{
		Card* card = GenerateSingleCard(card_seeds[i]);
		fs << GetCardDetail(card) << endl;
		WriteSingleCardData(card_reps[i], card_strengths[i], fs);
		fs << endl;
		delete card;
	}
	fs.close();
	fs.clear();
}

void WriteDataDeckSorted(const vector<int>& card_seeds, const vector<vector<int>>& deck_list, const vector<MatchStat>& deck_stats, const vector<int>& sorted_deck_indices, int start_rank, int rank_step, int num_outputs, const char* filename) // Note: the rank passed in to the function should be zero-indexed (while in the file output it is one-indexed
{
	int deck_num = deck_list.size();
	int deck_size = deck_list[0].size();

	ofstream fs(filename);
	fs << num_outputs << endl;
	fs << deck_size << endl;
	int rank = start_rank;
	int i = 0;
	for (; i < num_outputs && rank < deck_num; i++, rank += rank_step)
	{
		int index = sorted_deck_indices[rank];
		fs << rank + 1 << " " << deck_stats[index].eval << " "
			<< deck_stats[index].num_wins << " " << deck_stats[index].num_losses << " " << deck_stats[index].total_num << " " << endl;
		// index in the card seed list
		for (int j = 0; j < deck_size; j++)
			fs << deck_list[index][j] << " ";
		fs << endl;
		// the actual seeds
		for (int j = 0; j < deck_size; j++)
			fs << card_seeds[deck_list[index][j]] << " ";
		fs << endl;
	}
	if (i < num_outputs && rank >= deck_num)
		cout << "Warning: not enough decks for outputting." << endl;
	fs.close();
	fs.clear();		
}

void PrepareData(const vector<int>& card_seeds, const vector<MatchStat>& card_stats, vector<CardRep>& card_reps, vector<double>& card_strengths, vector<double>& card_weights, bool write_raw_to_file = true, bool write_processed_to_file = true)
{
	int p = card_seeds.size();

	GetCardRepsFromSeeds(card_seeds, card_reps);

	card_strengths.resize(p);
	card_weights.resize(p);
	for (int i = 0; i < p; i++)
	{
		card_strengths[i] = card_stats[i].eval;
		card_weights[i] = card_stats[i].total_participation;
	}

	if (write_raw_to_file)
	{
		// save raw match data to a file (card are only recorded with seeds; more match stats preserved)
		WriteRawData(card_seeds, card_stats);
	}
		
	if (write_processed_to_file)
	{
		// save the match data to a file (no card info)
		WriteData(card_reps, card_strengths);

		// save the match data with card info to a file
		WriteDataHuman(card_seeds, card_reps, card_strengths);
	}
}

void ReadRawData(vector<int>& card_seeds, vector<MatchStat>& card_stats, const char* filename = Match_Card_Data_Path_Raw.c_str())
{
	ifstream fs(filename);
	if (!fs.is_open())
        {
                cout << "Error occurred when opening data file (due to file existence or permission issues)" << endl;
                fs.clear();
                exit(1);
        }
	int p;
	fs >> p;
	card_seeds.resize(p);
	card_stats.resize(p);
	for (int i = 0; i < p; i++)
		fs >> card_seeds[i] >> card_stats[i].eval
			>> card_stats[i].num_wins >> card_stats[i].num_losses >> card_stats[i].total_num 
			>> card_stats[i].win_contribution >> card_stats[i].total_participation;
	fs.close();
	fs.clear();	
}

void ReadData(vector<CardRep>& card_reps, vector<double>& card_strengths, const char* filename = Match_Card_Data_Path_Processed.c_str())
{
	// often the match data file and read from it
	ifstream fs(filename);
	if (!fs.is_open())
	{
		cout << "Error occurred when opening data file (due to file existence or permission issues)" << endl;
		fs.clear();
		exit(1);
	}
	int p;
	fs >> p;
	card_reps.resize(p);
	card_strengths.resize(p);
	for (int i = 0; i < p; i++)
	{
		int tmp_rep_len;
		fs >> tmp_rep_len;
		char tmp_ch;
		fs >> tmp_ch >> tmp_ch; // read two colons
		for (int j = 0; j < tmp_rep_len; j++)
		{
			int tmp_choice;
			fs >> tmp_choice;
			fs >> tmp_ch; // read a comma
			int tmp_term_len;
			fs >> tmp_term_len;
			fs >> tmp_ch; // read a colon
			vector<double> tmp_term_info(tmp_term_len);
			for (int k = 0; k < tmp_term_len; k++)
				fs >> tmp_term_info[k];
			fs >> tmp_ch; // read a semicolon
			card_reps[i].push_back(NodeRep(tmp_choice, tmp_term_info));
		}
		fs >> card_strengths[i];
	}
	fs.close();
	fs.clear();
}

void ReadDeckData(vector<vector<int>>& deck_list, vector<MatchStat>& deck_stats, const char* filename)
{
	ifstream fs(filename);
	if (!fs.is_open())
	{
		cout << "Error occurred when opening data file (due to file existence or permission issues)" << endl;
		fs.clear();
		exit(1);
	}
	int deck_num;
	int deck_size; 
	fs >> deck_num >> deck_size;
	deck_list.resize(deck_num);
	deck_stats.resize(deck_num);
	for (int i = 0; i < deck_num; i++)
	{
		int rank;
		fs >> rank // not recorded
			>> deck_stats[i].eval
			>> deck_stats[i].num_wins >> deck_stats[i].num_losses >> deck_stats[i].total_num;
		deck_stats[i].win_contribution = deck_stats[i].num_wins - deck_stats[i].num_losses;
		deck_stats[i].total_participation = deck_stats[i].total_num;
		// index in the card seed list
		deck_list[i].resize(deck_size);
		for (int j = 0; j < deck_size; j++)
			fs >> deck_list[i][j];
		// the actual seeds, skipped for now, as we always require a card list file (seeds) to be read
		int tmp_seed;
		for (int j = 0; j < deck_size; j++)
			fs >> tmp_seed;
	}
	fs.close();
	fs.clear();
}

void SplitTrainValidate(const vector<CardRep>& inputs, const vector<double>& labels, const vector<double>& weights, vector<CardRep>& train_inputs, vector<CardRep>& validate_inputs, vector<double>& train_labels, vector<double>& validate_labels, vector<double>& train_weights, vector<double>& validate_weights)
{
	double train_ratio = 0.8;
	int p = inputs.size();
	int train_size = (int)(train_ratio * p);

	train_inputs.resize(train_size);
	train_labels.resize(train_size);
	train_weights.resize(train_size);
	int i;
	for (i = 0; i < train_size; i++)
	{
		train_inputs[i] = inputs[i];
		train_labels[i] = labels[i];
		train_weights[i] = weights[i];
	}
	validate_inputs.resize(p - train_size);
	validate_labels.resize(p - train_size);
	validate_weights.resize(p - train_size);
	for (int j = 0; i < p; i++, j++)
	{
		validate_inputs[j] = inputs[i];
		validate_labels[j] = labels[i];
		validate_weights[j] = weights[i];
	}	
}

torch::Device* InitCardModel(CardNet& model) // return the pointer to device
{
	torch::DeviceType device_type;
	if (torch::cuda::is_available())
	{
		std::cout << "CUDA available! Using GPU." << std::endl;
		device_type = torch::kCUDA;
	}
        else
	{
		std::cout << "Using CPU." << std::endl;
		device_type = torch::kCPU;
	}
	torch::Device* device_ptr = new torch::Device(device_type);
	model.to(*device_ptr);
	model.to(torch::kDouble);
	return device_ptr;
}

void TrainCardModel(const vector<CardRep>& train_reps, const vector<double>& train_strengths, const vector<double>& train_weights, const vector<CardRep>& validate_reps, const vector<double>& validate_strengths, const vector<double>& validate_weights, CardNet& model, int seed, const char* filename = Card_Model_Path.c_str(), const char* log_file_name = Card_Train_Log_Path.c_str(), const char* train_file = Card_Train_Correlation_Path.c_str(), const char* validate_file = Card_Validate_Correlation_Path.c_str())
{
	torch::Device* device_ptr = InitCardModel(model);

	ofstream log_fs(log_file_name);
	TrainCardStrengthPredictor(train_reps, train_strengths, train_weights, validate_reps, validate_strengths, validate_weights, model, *device_ptr, seed, log_fs, train_file, validate_file);
	log_fs.close();
	log_fs.clear();

	// write the trained model to a file
	torch::serialize::OutputArchive output_archive;
	model.save(output_archive);
	output_archive.save_to(filename);

	delete device_ptr;
}

void LoadCardModel(CardNet& model, const char* filename = Card_Model_Path.c_str())
{
	torch::Device* device_ptr = InitCardModel(model);

	torch::serialize::InputArchive input_archive;
	input_archive.load_from(filename);
	model.load(input_archive);

	delete device_ptr;
}

int main(int argc, char* argv[]) // argument order, if supplied: mode, seed, file paths (with different semantics among modes)
{
	int seed = 0;
	char ch = 'y';

	unsigned n = 20; // cards in a deck

	cout << "Select Mode: " << endl;
	cout << "0 (Default): Generate Random Cards Freely." << endl;
	cout << "1 : Generate Random Cards with Specified Seeds." << endl;
	cout << "2 : Play with yourself with Specified Seeds." << endl;
	cout << "3 : Play with Random AI with Randomly Generated Decks." << endl;
	cout << "4 : Simulate AI Vs AI matches (with same AI) for evaluating cards (decks) with evolutionary deck building and matching scheme." << endl;
	cout << "5 : Simulate AI Vs AI matches (with same AI) for evaluating cards (decks) with random deck building and matching scheme." << endl;
	cout << "6 : Read raw results of simulated matches for training predictors" << endl;
	// cout << "7 : Read preprocessed results of simulated matches for training predictors" << endl;
	cout << "8 : Read current models of predictors for predictions" << endl;
	cout << "9 : Simulate AI Vs AI matches between (different) AI's" << endl;
	cout << "10 : Simulate AI Vs AI matches (with same AI) between different two small sets of given decks." << endl;
	cout << "11 : Test new random cards against an environment represented with a small number of (evolved) decks to see how network prediction performs." << endl;
	cout << "12 : Test new random cards against an environment represented with a large number of (random) decks to see how network prediction performs." << endl;
	cout << "13 : Update the prediction test results against a prediction model (may or may not be trained from a different environment)." << endl;
	cout << "14 : Miscellaneous performance tests." << endl;
	
	int mode;
	if (argc > 1)
	{
		mode = atoi(argv[1]);
		cout << "Mode selected: " << mode << endl;
	}
	else
	{
		cin >> mode;
	}

	switch (mode)
	{
	/*case 16:
		{
			int p = 1000;
			
			if (argc > 2)
                        {
                                seed = atoi(argv[2]);
                        }
                        else
                        {
                                cout << "Input Seed" << endl;
                                cin >> seed;
                        }
			
			Card_Model_Path = "model_evolved.pt";
			if (argc > 3)
				Card_Model_Path = argv[3];

			string Card_Prediction_Path_Machine = "test_prediction_random_machine.txt";
			if (argc > 4)
				Card_Prediction_Path_Machine = argv[4];
			size_t post_fix_pos = Card_Prediction_Path_Machine.rfind("machine");
			if (post_fix_pos == string::npos)
			{
				cout << "Error: the path for (raw) card data file must contain \"machine\"." << endl;
				exit(1);
			}
			string Card_Prediction_Path_Human = Card_Prediction_Path_Machine;
			Card_Prediction_Path_Human.replace(post_fix_pos, 7, "human");
			
			vector<int> seed_list = GenerateCardSetSeeds(p, seed);
		
			// load network model
			CardNet card_net;
			LoadCardModel(card_net);

			ofstream fs_machine(Card_Prediction_Path_Machine.c_str());
			ofstream fs_human(Card_Prediction_Path_Human.c_str());
			fs_machine << p << endl;
			fs_human << p << endl;
			for (int i = 0; i < p; i++)
			{
				int tmp_seed = seed_list[i];
				fs_machine << tmp_seed << " ";
				Card* card = GenerateSingleCard(tmp_seed);
				fs_human << GetCardDetail(card) << endl;
				double predicted_str = PredictCardStrength(card, card_net);
				DeleteCard(card);
				fs_machine << predicted_str << endl;
				fs_human << "Predicted Strength: " << predicted_str << endl << endl;
			}
			fs_machine.close();
			fs_machine.clear();
			fs_human.close();
			fs_human.clear();
		}
		break;*/
	case 14:
		{
			int n_test_cards = 1000000;
			
			if (argc > 2)
                        {
                                seed = atoi(argv[2]);
                        }
                        else
                        {
                                cout << "Input Seed" << endl;
                                cin >> seed;
                        }

			if (argc > 3)
				Card_Model_Path = argv[3];
			
			// load network model
			CardNet card_net;
			LoadCardModel(card_net);

			vector<int> seed_list = GenerateCardSetSeeds(n_test_cards, seed);
			vector<Card*> card_list(n_test_cards);
			
			time_t timer_0 = time(NULL);

			for (int i = 0; i < n_test_cards; i++)
				card_list[i] = GenerateSingleCard(seed_list[i]);
				
			time_t timer_1 = time(NULL);

			for (int i = 0; i < n_test_cards; i++)
				PredictCardStrength(card_list[i], card_net);

			time_t timer_2 = time(NULL);

			for (int i = 0; i < n_test_cards; i++)
				DeleteCard(card_list[i]);

			time_t timer_3 = time(NULL);
			
			/* performance report */
			cout << endl;
			cout << "Total number cards tested: " << n_test_cards << endl;
			double generate_time = difftime(timer_1, timer_0);
			cout << "Card generation time: " << generate_time << endl;
			double predict_time = difftime(timer_2, timer_1);
			cout << "Card strength prediction time (including preprocessing inputs): " << predict_time << endl;
			double delete_time = difftime(timer_3, timer_2);
			cout << "Card deletion time: " << delete_time << endl;
		}
		break;
	case 13:
		{
			// seed field will exist but not really used
			string Card_Prediction_Path = "test_prediction_machine.txt";
			if (argc > 3)
				Card_Prediction_Path = argv[3];

			if (argc > 4)
				Card_Model_Path = argv[4];

			string Cross_Over_Test_Path = "cross_over_test.txt";
			if (argc > 5)
				Cross_Over_Test_Path = argv[5];

			// load network model
			CardNet card_net;
			LoadCardModel(card_net);

			ifstream in_fs(Card_Prediction_Path.c_str());
			ofstream out_fs(Cross_Over_Test_Path.c_str());
			int n_test_cards;
			in_fs >> n_test_cards;
			out_fs << n_test_cards << endl;
			for (int i = 0; i < n_test_cards; i++)
			{
				int new_seed, old_seed;
				double new_eval, old_eval;
				double new_pred, old_pred;
				int new_wins, new_losses, new_total, old_wins, old_losses, old_total;
				double new_win_contribution, new_total_participation, old_win_contribution, old_total_participation;
				
				// read
				in_fs >> new_seed >> new_pred >> new_eval >> new_wins >> new_losses >> new_total >> new_win_contribution >> new_total_participation
					>> old_seed >> old_pred >> old_eval >> old_wins >> old_losses >> old_total >> old_win_contribution >> old_total_participation;
				
				// redo prediction and overwrite
				Card* new_card = GenerateSingleCard(new_seed);
				new_pred = PredictCardStrength(new_card, card_net);
				DeleteCard(new_card);
				Card* old_card = GenerateSingleCard(old_seed);
				old_pred = PredictCardStrength(old_card, card_net);
				DeleteCard(old_card);

				// write
				out_fs << new_seed << " " << new_pred << " " << new_eval << " " << new_wins << " " << new_losses << " " << new_total << " " << new_win_contribution << " " << new_total_participation << " "
					<< old_seed << " " << old_pred << " " << old_eval << " " << old_wins << " " << old_losses << " " << old_total << " " << old_win_contribution << " " << old_total_participation << endl;

			}
			in_fs.close();
			in_fs.clear();
			out_fs.close();
			out_fs.clear();
		}
		break;
	case 12:
		{
			int n_test_cards = 100;
			int match_num = 4 * 900; // total number of match pairs to test for each new card

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;

			string Card_Path = "match_card_data_raw_random.txt";
			if (argc > 3)
				Card_Path = argv[3];
			
			string Deck_Path = "match_deck_data_random_all.txt";
			if (argc > 4)
				Deck_Path = argv[4];

			Card_Model_Path = "model_random.pt";
			if (argc > 5)
				Card_Model_Path = argv[5];
			
			string Card_Prediction_Path_Machine = "test_prediction_random_machine.txt";
			if (argc > 6)
				Card_Prediction_Path_Machine = argv[6];
			size_t post_fix_pos = Card_Prediction_Path_Machine.rfind("machine");
			if (post_fix_pos == string::npos)
			{
				cout << "Error: the path for (raw) card data file must contain \"machine\"." << endl;
				exit(1);
			}
			string Card_Prediction_Path_Human = Card_Prediction_Path_Machine;
			Card_Prediction_Path_Human.replace(post_fix_pos, 7, "human");
			
			// read card data
			vector<int> seed_list;
			vector<MatchStat> card_stats_orig;
			ReadRawData(seed_list, card_stats_orig, Card_Path.c_str());
			int card_num = seed_list.size();
			
			// read deck data
			vector<vector<int>> deck_list_orig;
			vector<MatchStat> deck_stats_orig; // the original stats from when the deck where initially created and tested, not actually used here
			ReadDeckData(deck_list_orig, deck_stats_orig, Deck_Path.c_str());
			int deck_num = deck_list_orig.size();
			int deck_size = deck_list_orig[0].size();

			// load network model
			CardNet card_net;
			LoadCardModel(card_net);

			unsigned ai_level = 2;
			
			vector<int> new_seed_list = GenerateCardSetSeeds(n_test_cards, seed);
			
			time_t timer_0 = time(NULL);

			int turn_count = 0;

			ofstream fs_machine(Card_Prediction_Path_Machine.c_str());
			ofstream fs_human(Card_Prediction_Path_Human.c_str());
			fs_machine << n_test_cards << endl;
			fs_human << n_test_cards << endl;
			seed_list.resize(card_num + 1); // expand the size by one to test one new card per time
			for (int m = 0; m < n_test_cards; m++)
			{
				int tmp_seed = new_seed_list[m];
				cout << endl << "Testing card " << m+1 << "/" << n_test_cards << "; Seed: " << tmp_seed << endl;

				// simulation against the environment
				seed_list[card_num] = tmp_seed;
				vector<MatchStat> card_stats = card_stats_orig; // make a copy so that we always start from the same original version
				card_stats.push_back(MatchStat());
				vector<vector<int>> deck_list = deck_list_orig; // make a copy so that we always start from the same original version
				int replaced_card_index; // determined in the function
				ReplaceSignificantCardInDeckPool(deck_list, replaced_card_index, card_num, card_num);
				// reset the replaced card for this test (could just reset all, would be same relatively between the two; in absolute sense look better in this way due to the normalization)
				card_stats[replaced_card_index] = MatchStat();
				vector<MatchStat> deck_stats(deck_num); // not really used
				for (int i = 0; i < match_num; i++) // when the number of decks is large we can't affort pair-wise, so we do it randomly
				{
					int index_a = GetGiglRandInt(deck_num);
					int index_b = GetGiglRandInt(deck_num);
					cout << "Match Pair " << i << ": Modified Deck " << index_a << " VS Original Deck " << index_b << "." << endl;
					turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[index_a], deck_list_orig[index_b], card_stats, deck_stats[index_a], deck_stats_orig[index_b], deck_size);
				}
				UpdateStatEvals(card_stats);

				// save new card info, including network prediction and test results
				fs_machine << tmp_seed << " ";
				Card* card = GenerateSingleCard(tmp_seed);
				fs_human << "New Card: " << endl << endl << GetCardDetail(card) << endl;
				double predicted_str = PredictCardStrength(card, card_net);
				DeleteCard(card);
				fs_machine << predicted_str << " ";
				fs_human << "Predicted Strength: " << predicted_str << endl;
				double tested_str = card_stats[card_num].eval;
				fs_machine << tested_str << " "
					<< card_stats[card_num].num_wins << " " << card_stats[card_num].num_losses << " " << card_stats[card_num].total_num << " "
					<< card_stats[card_num].win_contribution << " " << card_stats[card_num].total_participation << " ";
				fs_human << "Tested Strength: " << tested_str << " " << endl << endl;

				// save replaced card info, including network prediction and test results
				tmp_seed = seed_list[replaced_card_index];
				fs_machine << tmp_seed << " ";
				card = GenerateSingleCard(tmp_seed);
				fs_human << "Replaced Card: " << endl << endl << GetCardDetail(card) << endl;
				predicted_str = PredictCardStrength(card, card_net);
				DeleteCard(card);
				fs_machine << predicted_str << " ";
				fs_human << "Predicted Strength: " << predicted_str << endl;
				tested_str = card_stats[replaced_card_index].eval;
				fs_machine << tested_str << " "
					<< card_stats[replaced_card_index].num_wins << " " << card_stats[replaced_card_index].num_losses << " " << card_stats[replaced_card_index].total_num << " "
					<< card_stats[replaced_card_index].win_contribution << " " << card_stats[replaced_card_index].total_participation << endl;
				fs_human << "Tested Strength: " << tested_str << " " << endl << endl << "---------------------------------------------" << endl << endl;
			}
			fs_machine.close();
			fs_machine.close();
			fs_human.clear();	
			fs_human.clear();

			time_t timer_1 = time(NULL);
	
			/* performance report */
			cout << endl;
			cout << "Total number of decks tested: " << (n_test_cards + 1) * deck_num << endl;
			cout << "Total number of match pairs tested: " << n_test_cards * match_num << endl; 
			cout << "Total number of match turns simulated: " << turn_count << endl; 
			double total_time = difftime(timer_1, timer_0);
			cout << "Total testing time (including writing results to the files): " << total_time << endl;
		}
		break;
	case 11:
		{
			int n_test_cards = 100;
			int num_pair_matches = 4; // number of match pairs between each pair of decks

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;

			string Card_Path = "match_card_data_raw_evolved.txt";
			if (argc > 3)
				Card_Path = argv[3];
			
			string Deck_Path = "match_deck_data_evolved.txt";
			if (argc > 4)
				Deck_Path = argv[4];

			Card_Model_Path = "model_evolved.pt";
			if (argc > 5)
				Card_Model_Path = argv[5];
			
			string Card_Prediction_Path_Machine = "test_prediction_evolved_machine.txt";
			if (argc > 6)
				Card_Prediction_Path_Machine = argv[6];
			size_t post_fix_pos = Card_Prediction_Path_Machine.rfind("machine");
			if (post_fix_pos == string::npos)
			{
				cout << "Error: the path for (raw) card data file must contain \"machine\"." << endl;
				exit(1);
			}
			string Card_Prediction_Path_Human = Card_Prediction_Path_Machine;
			Card_Prediction_Path_Human.replace(post_fix_pos, 7, "human");
			
			// read card data
			vector<int> seed_list;
			vector<MatchStat> card_stats_orig;
			ReadRawData(seed_list, card_stats_orig, Card_Path.c_str());
			int card_num = seed_list.size();
			
			// read deck data
			vector<vector<int>> deck_list_orig;
			vector<MatchStat> deck_stats_orig; // the original stats from when the deck where initially created and tested, not actually used here
			ReadDeckData(deck_list_orig, deck_stats_orig, Deck_Path.c_str());
			int deck_num = deck_list_orig.size();
			int deck_size = deck_list_orig[0].size();

			// load network model
			CardNet card_net;
			LoadCardModel(card_net);

			unsigned ai_level = 2;
			
			vector<int> new_seed_list = GenerateCardSetSeeds(n_test_cards, seed);
			
			time_t timer_0 = time(NULL);

			int turn_count = 0;

			ofstream fs_machine(Card_Prediction_Path_Machine.c_str());
			ofstream fs_human(Card_Prediction_Path_Human.c_str());
			fs_machine << n_test_cards << endl;
			fs_human << n_test_cards << endl;
			seed_list.resize(card_num + 1); // expand the size by one to test one new card per time
			for (int m = 0; m < n_test_cards; m++)
			{
				int tmp_seed = new_seed_list[m];
				cout << endl << "Testing card " << m+1 << "/" << n_test_cards << "; Seed: " << tmp_seed << endl;

				// simulation against the environment
				seed_list[card_num] = tmp_seed;
				vector<MatchStat> card_stats = card_stats_orig; // make a copy so that we always start from the same original version
				card_stats.push_back(MatchStat());
				vector<vector<int>> deck_list = deck_list_orig; // make a copy so that we always start from the same original version
				int replaced_card_index; // determined in the function
				ReplaceSignificantCardInDeckPool(deck_list, replaced_card_index, card_num, card_num);
				// reset the replaced card for this test (could just reset all, would be same relatively between the two; in absolute sense look better in this way due to the normalization)
				card_stats[replaced_card_index] = MatchStat();
				vector<MatchStat> deck_stats(deck_num); // not really used
				for (int i = 0; i < deck_num; i++) // when the number of decks is small, we can do pair-wise
				{
					for (int j = 0; j < deck_num; j++)
					{
						cout << "Modified Deck " << i << " VS Original Deck " << j << "." << endl;
						for (int k = 0; k < num_pair_matches; k++)
						{
							cout << "Match Pair " << k << ":" << endl;
							turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_list_orig[j], card_stats, deck_stats[i], deck_stats_orig[j], deck_size);
						}
					}
				}
				UpdateStatEvals(card_stats);

				// save new card info, including network prediction and test results
				fs_machine << tmp_seed << " ";
				Card* card = GenerateSingleCard(tmp_seed);
				fs_human << "New Card: " << endl << endl << GetCardDetail(card) << endl;
				double predicted_str = PredictCardStrength(card, card_net);
				DeleteCard(card);
				fs_machine << predicted_str << " ";
				fs_human << "Predicted Strength: " << predicted_str << endl;
				double tested_str = card_stats[card_num].eval;
				fs_machine << tested_str << " "
					<< card_stats[card_num].num_wins << " " << card_stats[card_num].num_losses << " " << card_stats[card_num].total_num << " "
					<< card_stats[card_num].win_contribution << " " << card_stats[card_num].total_participation << " ";
				fs_human << "Tested Strength: " << tested_str << " " << endl << endl;

				// save replaced card info, including network prediction and test results
				tmp_seed = seed_list[replaced_card_index];
				fs_machine << tmp_seed << " ";
				card = GenerateSingleCard(tmp_seed);
				fs_human << "Replaced Card: " << endl << endl << GetCardDetail(card) << endl;
				predicted_str = PredictCardStrength(card, card_net);
				DeleteCard(card);
				fs_machine << predicted_str << " ";
				fs_human << "Predicted Strength: " << predicted_str << endl;
				tested_str = card_stats[replaced_card_index].eval;
				fs_machine << tested_str << " "
					<< card_stats[replaced_card_index].num_wins << " " << card_stats[replaced_card_index].num_losses << " " << card_stats[replaced_card_index].total_num << " "
					<< card_stats[replaced_card_index].win_contribution << " " << card_stats[replaced_card_index].total_participation << endl;
				fs_human << "Tested Strength: " << tested_str << " " << endl << endl << "---------------------------------------------" << endl << endl;
			}
			fs_machine.close();
			fs_machine.close();
			fs_human.clear();	
			fs_human.clear();

			time_t timer_1 = time(NULL);
	
			/* performance report */
			cout << endl;
			cout << "Total number of decks tested: " << (n_test_cards + 1) * deck_num << endl;
			cout << "Total number of match pairs tested: " << n_test_cards * deck_num * deck_num * num_pair_matches << endl; 
			cout << "Total number of match turns simulated: " << turn_count << endl; 
			double total_time = difftime(timer_1, timer_0);
			cout << "Total testing time (including writing results to the files): " << total_time << endl;
		}
		break;
	case 10:
		{
			int num_pair_matches = 64; // number of match pairs between each pair of decks

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;

			if (argc <= 3)
			{
				cout << "Error: card info (raw) file path not provided." << endl;
				exit(1);
			}
			
			string Card_Path = argv[3];

			if (argc <= 5)
			{
				cout << "Error: deck info file paths not provided or insufficient." << endl;
				exit(1);
			}

			string Deck_A_Path = argv[4];
			string Deck_B_Path = argv[5];

			string Deck_Post_Simulation_Path = "deck_post_simulation.txt";
			if (argc > 6)
				Deck_Post_Simulation_Path = argv[6];
			
			// read card data
			vector<int> seed_list;
			vector<MatchStat> card_stats; // it is questionable whether we should clear this before simulation, but these are not used here so it should be fine for now
			ReadRawData(seed_list, card_stats, Card_Path.c_str());
			
			// read deck data
			vector<vector<int>> deck_list_a, deck_list_b;
			vector<MatchStat> deck_stats_a, deck_stats_b; // not actually used here, the original stats from when the deck where initially created and tested
			ReadDeckData(deck_list_a, deck_stats_a, Deck_A_Path.c_str());
			ReadDeckData(deck_list_b, deck_stats_b, Deck_B_Path.c_str());
			int deck_num_a = deck_list_a.size();
			int deck_num_b = deck_list_b.size();
			int deck_size = deck_list_a[0].size();

			unsigned ai_level = 2;

			time_t timer_0 = time(NULL);

			int turn_count = 0;

			ofstream fs(Deck_Post_Simulation_Path.c_str());
			fs << deck_num_a << " " << deck_num_b << endl;
			for (int i = 0; i < deck_num_a; i++)
			{
				for (int j = 0; j < deck_num_b; j++)
				{
					MatchStat tmp_stat_a, tmp_stat_b; // only tmp_stat_a is recorded to output (well they should be symmetric)
					cout << "Deck " << i << " from the first list VS Deck " << j << " from the second list." << endl;
					for (int k = 0; k < num_pair_matches; k++)
					{
						cout << "Match Pair " << k << ":" << endl;
						turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list_a[i], deck_list_b[j], card_stats, tmp_stat_a, tmp_stat_b, deck_size);
					}
					tmp_stat_a.UpdateEval();
					tmp_stat_b.UpdateEval(); // not actually necessary
					fs << tmp_stat_a.eval << " ";
				}
				fs << endl;
			}
			fs.close();
			fs.clear();	
			
			time_t timer_1 = time(NULL);
			
			/* performance report */
			cout << endl;
			cout << "Total number of decks tested: " << deck_num_a + deck_num_b << endl;
			cout << "Total number of match pairs tested: " << deck_num_a * deck_num_b * num_pair_matches << endl; 
			cout << "Total number of match turns simulated: " << turn_count << endl; 
			double total_time = difftime(timer_1, timer_0);
			cout << "Total testing time (including writing results to the file): " << total_time << endl;
		}
		break;
	case 9:
		{
			int p = 50;
			int deck_num = 100;

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;

			vector<int> seed_list = GenerateCardSetSeeds(p, seed);

			vector<vector<int>> deck_list; // storing card indices in the seed list (not the seeds themselves)
			for (int i = 0; i < deck_num; i++)
				deck_list.push_back(CreateRandomSelection(p, n));

			// pair-wise matches (duplicate the same pair twice for a different player go first)
			unsigned ai_level_a, ai_level_b;
			cout << "Input AI level for the first AI - 0: Pure Random; 1 ~ 9: Search Based (higher number does more trials)" << endl;
			cin >> ai_level_a;
			cout << "Input AI level for the first AI - 0: Pure Random; 1 ~ 9: Search Based (higher number does more trials)" << endl;
			cin >> ai_level_b;
			TestAIs(ai_level_a, ai_level_b, seed_list, deck_list, deck_num, n);
		}
		break;
	case 8:
		{
			// seed field will still exist but not used (argv[2])
			if (argc > 3)
				Card_Model_Path = argv[3];
			
			CardNet card_net;
			LoadCardModel(card_net);

			cout << "Trying the Predictor on New Cards" << endl;
			while (true)
			{
				cout << "Input seed (negative to quit)" << endl;
				cin >> seed;
				if (seed < 0)
					break;
				Card* card = GenerateSingleCard(seed);
				cout << endl << GetCardDetail(card) << endl;
				cout <<  "Strength Prediction: " << PredictCardStrength(card, card_net) << endl;
				DeleteCard(card);
			}
		}
		break;
	/*case 7:
		{
			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			srand(seed);
			torch::manual_seed(seed);
			
			if (argc > 3)
				Match_Card_Data_Path_Processed = argv[3];

			if (argc > 4)
				Card_Model_Path = argv[4];

			if (argc > 5)
				Card_Train_Log_Path = argv[5];

			if (argc > 6)
				Card_Train_Correlation_Path = argv[6];
			
			if (argc > 7)
				Card_Validate_Correlation_Path = argv[7];
			
			vector<CardRep> card_reps;
			vector<double> card_strengths;
			ReadData(card_reps, card_strengths);
			
			vector<CardRep> train_reps, validate_reps;
			vector<double> train_strengths, validate_strengths;
			SplitTrainValidate(card_reps, card_strengths, train_reps, validate_reps, train_strengths, validate_strengths);
		
			time_t timer_0 = time(NULL);
				
			cout << "Training Card Strength Predictor ..." << endl;
			CardNet card_net;
			TrainCardModel(train_reps, train_strengths, validate_reps, validate_strengths, card_net, seed);
			cout << "Training Done" << endl;
			
			time_t timer_1 = time(NULL);

			cout << endl;
			double train_time = difftime(timer_1, timer_0);
			cout << "Training time: " << train_time << endl;

			cout << "Trying the Predictor on New Cards" << endl;
			while (true)
			{
				cout << "Input seed (negative to quit)" << endl;
				cin >> seed;
				if (seed < 0)
					break;
				Card* card = GenerateSingleCard(seed);
				cout << endl << GetCardDetail(card) << endl;
				cout <<  "Strength Prediction: " << PredictCardStrength(card, card_net) << endl;
				DeleteCard(card);
			}
		}
		break;*/
	case 6:
		{
			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			srand(seed);
			torch::manual_seed(seed);

			if (argc > 3)
			{
				Match_Card_Data_Path_Raw = argv[3];
				size_t post_fix_pos = Match_Card_Data_Path_Raw.rfind("raw");
				if (post_fix_pos == string::npos)
				{
					cout << "Error: the path for (raw) card data file must contain \"raw\"." << endl;
					exit(1);
				}
				Match_Card_Data_Path_Processed = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Processed.replace(post_fix_pos, 3, "processed");
				Match_Card_Data_Path_Human = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Human.replace(post_fix_pos, 3, "human");
			}

			if (argc > 4)
				Card_Model_Path = argv[4];

			if (argc > 5)
				Card_Train_Log_Path = argv[5];

			if (argc > 6)
				Card_Train_Correlation_Path = argv[6];
			
			if (argc > 7)
				Card_Validate_Correlation_Path = argv[7];
				
			vector<int> seed_list;
			vector<MatchStat> card_stats;
			ReadRawData(seed_list, card_stats);

			/*// convert to strengths to rank
			int card_num = card_stats.size();
			vector<int> card_indices(card_num);
			SortStatInIndices(card_stats, card_indices);
			for (int i = 0; i < card_num; i++)
				card_stats[card_indices[i]].eval = 1.0 - 2.0 * i / (double)(card_num - 1); // normalized ranking*/

			vector<CardRep> card_reps;
			vector<double> card_strengths;
			vector<double> card_weights;
			PrepareData(seed_list, card_stats, card_reps, card_strengths, card_weights, false); // false means don't rewrite the raw data (it will rewrite the processed and human data)

			vector<CardRep> train_reps, validate_reps;
			vector<double> train_strengths, validate_strengths;
			vector<double> train_weights, validate_weights;
			SplitTrainValidate(card_reps, card_strengths, card_weights, train_reps, validate_reps, train_strengths, validate_strengths, train_weights, validate_weights);

			time_t timer_0 = time(NULL);
				
			cout << "Training Card Strength Predictor ..." << endl;
			CardNet card_net;
			TrainCardModel(train_reps, train_strengths, train_weights, validate_reps, validate_strengths, validate_weights, card_net, seed);
			cout << "Training Done" << endl;

			time_t timer_1 = time(NULL);
			
			cout << endl;
			double train_time = difftime(timer_1, timer_0);
			cout << "Training time (including writting to the log file and saving the trained model): " << train_time << endl;

			cout << "Trying the Predictor on New Cards" << endl;
			while (true)
			{
				cout << "Input seed (negative to quit)" << endl;
				cin >> seed;
				if (seed < 0)
					break;
				Card* card = GenerateSingleCard(seed);
				cout << endl << GetCardDetail(card) << endl;
				cout <<  "Strength Prediction: " << PredictCardStrength(card, card_net) << endl;
				DeleteCard(card);
			}
		}
		break;
	case 5:
		{
			/* run simulation */
			int p = 1000; // size of the card pool
			int deck_num = 3000; // total number of decks
			int match_num = 200000; // total number of pair matches

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;
			
			if (argc > 3)
			{
				Match_Card_Data_Path_Raw = argv[3];
				size_t post_fix_pos = Match_Card_Data_Path_Raw.rfind("raw");
				if (post_fix_pos == string::npos)
				{
					cout << "Error: the path for (raw) card data file must contain \"raw\"." << endl;
					exit(1);
				}
				Match_Card_Data_Path_Processed = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Processed.replace(post_fix_pos, 3, "processed");
				Match_Card_Data_Path_Human = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Human.replace(post_fix_pos, 3, "human");
			}
			
			string Match_Deck_Data_Path_All = "match_deck_data_all.txt";
			if (argc > 4)
				Match_Deck_Data_Path_All = argv[4];
			string Match_Deck_Data_Path_Top = "match_deck_data_top.txt";
			if (argc > 5)
				Match_Deck_Data_Path_Top = argv[5];
			string Match_Deck_Data_Path_Skip = "match_deck_data_skip.txt";
			if (argc > 6)
				Match_Deck_Data_Path_Skip = argv[6];

			/*cout << "Input AI level - 0: Pure Random; 1 ~ 9: Search Based (higher number does more trials)" << endl;
			unsigned ai_level;
			cin >> ai_level;*/
			unsigned ai_level = 2;

			vector<MatchStat> card_stats(p);
			vector<MatchStat> deck_stats(deck_num);

			vector<int> seed_list = GenerateCardSetSeeds(p, seed);
			
			time_t timer_0 = time(NULL);

			vector<vector<int>> deck_list; // storing card indices in the seed list (not the seeds themselves)
			for (int i = 0; i < deck_num; i++)
				deck_list.push_back(CreateRandomSelection(p, n)); // problematic as some cards may not get selected

			int turn_count = 0;
			for (int i = 0; i < match_num; i++)
			{
				int index_a = GetGiglRandInt(deck_num);
				int index_b = GetGiglRandInt(deck_num);
				cout << "Match Pair " << i << ": Deck " << index_a << " VS Deck " << index_b << ". " << endl;
				turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[index_a], deck_list[index_b], card_stats, deck_stats[index_a], deck_stats[index_b], n);
			}
			UpdateStatEvals(card_stats);
			UpdateStatEvals(deck_stats);
			
			time_t timer_1 = time(NULL);
			
			/* performance report */
			cout << endl;
			cout << "Total number of decks tested: " << deck_num << endl;
			cout << "Total number of match pairs tested: " << match_num << endl; 
			cout << "Total number of match turns simulated: " << turn_count << endl; 
			double total_time = difftime(timer_1, timer_0);
			cout << "Total testing time: " << total_time << endl;
			
			/* prepare data for training/post processing */
			// card
			vector<CardRep> card_reps;
			vector<double> card_strengths;
			vector<double> card_weights;
			PrepareData(seed_list, card_stats, card_reps, card_strengths, card_weights);
			// decks
			vector<int> deck_indices(deck_num);
			SortStatInIndices(deck_stats, deck_indices);
			WriteDataDeckSorted(seed_list, deck_list, deck_stats, deck_indices, 0, 1, 3000, Match_Deck_Data_Path_All.c_str());
			WriteDataDeckSorted(seed_list, deck_list, deck_stats, deck_indices, 0, 1, 30, Match_Deck_Data_Path_Top.c_str());
			WriteDataDeckSorted(seed_list, deck_list, deck_stats, deck_indices, 49, 100, 30, Match_Deck_Data_Path_Skip.c_str());
			
			/* displaying */
			/*int display_num = 3;

			// sort according to the stats of cards			
			vector<int> card_indices(p);
			SortStatInIndices(card_stats, card_indices);
			MatchStat tmp_card_stat;
			Card* tmp_card;
			int card_ref_index;

			// top cards
			card_ref_index = -1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Top Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}

			// middle cards
			card_ref_index = (p - display_num) / 2 - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Middle Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}

			// bottom cards
			card_ref_index = p - display_num - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Bottom Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}*/		
		}
		break;
	case 4:
		{
			/* simulating and evolving */
			int p = 1000; // size of the card pool
			int deck_pool_size = 30; // number of active decks (will evolve during the simulation)
			int num_pair_matches_init = 2; // initial number of pair matches between each two decks
			int num_pair_matches_final = 8; // final number of pair matches between each two decks
			int num_evolve_iter = 1000;
			int deck_count = 30;
			int match_pair_count = 0;

			if (argc > 2)
			{
				seed = atoi(argv[2]);
			}
			else
			{
				cout << "Input Seed" << endl;
				cin >> seed;
			}
			cout << "Seed for simulation: " << seed << endl;
			
			if (argc > 3)
			{
				Match_Card_Data_Path_Raw = argv[3];
				size_t post_fix_pos = Match_Card_Data_Path_Raw.rfind("raw");
				if (post_fix_pos == string::npos)
				{
					cout << "Error: the path for (raw) card data file must contain \"raw\"." << endl;
					exit(1);
				}
				Match_Card_Data_Path_Processed = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Processed.replace(post_fix_pos, 3, "processed");
				Match_Card_Data_Path_Human = Match_Card_Data_Path_Raw;
				Match_Card_Data_Path_Human.replace(post_fix_pos, 3, "human");
			}

			string Match_Deck_Data_Path = "match_deck_data.txt";
			if (argc > 4)
				Match_Deck_Data_Path = argv[4];

			/*cout << "Input AI level - 0: Pure Random; 1 ~ 9: Search Based (higher number does more trials)" << endl;
			unsigned ai_level;
			cin >> ai_level;*/
			unsigned ai_level = 2;

			vector<MatchStat> card_stats(p);
			vector<MatchStat> deck_stats(deck_pool_size);

			vector<int> seed_list = GenerateCardSetSeeds(p, seed);

			vector<vector<int>> deck_list; // storing card indices in the seed list (not the seeds themselves)

			time_t timer_0 = time(NULL);

			int turn_count = 0;

			// initialization
			cout << "Creating and testing initial deck pool." << endl;
			for (int i = 0; i < deck_pool_size; i++)
			{
				vector<int> tmp_deck = CreateRandomSelectionSorted(p, n);
				bool is_duplicate;
				do // make sure we don't create duplicate decks
				{
					is_duplicate = false;
					for (int j = 0; j < i; j++)
						if (tmp_deck == deck_list[j])
						{
							is_duplicate = true;
							break;
						}
				} 
				while (is_duplicate);
				deck_list.push_back(tmp_deck);
			}
			for (int i = 0; i < deck_pool_size - 1; i++)
				for (int j = i+1; j < deck_pool_size; j++)
					for (int k = 0; k < num_pair_matches_init; k++)
					{
						cout << "Match Pair #" << ++match_pair_count << endl;
						turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_list[j], card_stats, deck_stats[i], deck_stats[j], n);
					}
			cout << endl;
			UpdateStatEvals(card_stats);
			UpdateStatEvals(deck_stats);

			time_t timer_1 = time(NULL);

			// evolving the deck pool and continue testing
			double t_init = 1.0; // intial "temperature"
			double ln_t_init = log(t_init);
			double t_final = 0.001;
			double ln_t_final = log(t_final);
			double action_probs_init[] = {0.7, 0.1, 0.2}; // new deck; cross-over; mutation
			double action_probs_final[] = {0.2, 0.5, 0.3}; // new deck; cross-over; mutation 	
			for (int iter = 1; iter <= num_evolve_iter; iter++)
			{
				cout << "Evolution iteration #" << iter << ": ";
				double progress = iter / (double)num_evolve_iter;
				double ln_t = ln_t_init + progress * (ln_t_final - ln_t_init); // temperature interpolated in log scale
				double t = exp(ln_t);
				int num_pair_matches = (int)(num_pair_matches_init + progress * (num_pair_matches_final - num_pair_matches_init));
				double action_probs[2]; // the third one is not used
				for (int i = 0; i < 2; i++)
					action_probs[i] = action_probs_init[i] + progress * (action_probs_final[i] - action_probs_init[i]);
				action_probs[1] += action_probs[0]; // cumulate
				double roll = GetGiglRandFloat();
				if (roll < action_probs[0]) // new deck
				{
					cout << "testing a new deck" << endl;
					turn_count += TestNewDeck(ai_level, seed_list, deck_list, card_stats, deck_stats, n, t, num_pair_matches, deck_count, match_pair_count);
				}
				else if (roll < action_probs[1]) // cross-over
				{
					cout << "testing the cross-overs of two existing decks" << endl;
					turn_count += TestCrossOver(ai_level, seed_list, deck_list, card_stats, deck_stats, n, t, num_pair_matches, deck_count, match_pair_count);
				}
				else // mutation
				{
					cout << "testing the mutation of an existing deck" << endl;
					turn_count += TestMutation(ai_level, seed_list, deck_list, card_stats, deck_stats, n, t, num_pair_matches, deck_count, match_pair_count);
				}
				UpdateStatEvals(card_stats); // deck stats should already be updated inside those "Test" functions
				cout << endl;
			}

			time_t timer_2 = time(NULL);

			// stop evolving and do the final round of tests
			cout << "Testing the final deck pool." << endl;
			for (int i = 0; i < deck_pool_size - 1; i++)
				for (int j = i+1; j < deck_pool_size; j++)
					for (int k = 0; k < num_pair_matches_final; k++)
					{
						cout << "Match Pair #" << ++match_pair_count << endl;
						turn_count += SimulatePairMatchBetweenDecks(ai_level, seed_list, deck_list[i], deck_list[j], card_stats, deck_stats[i], deck_stats[j], n);
					}
			cout << endl;
			UpdateStatEvals(card_stats);
			UpdateStatEvals(deck_stats);

			time_t timer_3 = time(NULL);

			/* performance report */
			cout << endl;
			cout << "Total number of decks tested: " << deck_count << endl;
			cout << "Total number of match pairs tested: " << match_pair_count << endl; 
			cout << "Total number of match turns simulated: " << turn_count << endl; 
			double init_time = difftime(timer_1, timer_0);
			cout << "Initial deck pool testing time: " << init_time << endl;
			double evolve_time = difftime(timer_2, timer_1);
			cout << "Evolving time: " << evolve_time << endl;
			double final_time = difftime(timer_3, timer_2);
			cout << "Final deck pool testing time: " << final_time << endl;	
			cout << "Total testing time: " << init_time + evolve_time + final_time << endl;

			/* prepare data for training/post processing */
			// cards
			vector<CardRep> card_reps;
			vector<double> card_strengths;
			vector<double> card_weights;
			PrepareData(seed_list, card_stats, card_reps, card_strengths, card_weights);
			// decks
			vector<int> deck_indices(deck_pool_size);
			SortStatInIndices(deck_stats, deck_indices);
			WriteDataDeckSorted(seed_list, deck_list, deck_stats, deck_indices, 0, 1, 30, Match_Deck_Data_Path.c_str());	
			
			/* displaying */
			/*int display_num = 3;

			// sort according to the stats of cards			
			vector<int> card_indices(p);
			SortStatInIndices(card_stats, card_indices);
			MatchStat tmp_card_stat;
			Card* tmp_card;
			int card_ref_index;

			// top cards
			card_ref_index = -1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Top Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}

			// middle cards
			card_ref_index = (p - display_num) / 2 - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Middle Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}

			// bottom cards
			card_ref_index = p - display_num - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Bottom Card #" << r << ":" << endl << endl;
				tmp_card_stat = card_stats[card_indices[r + card_ref_index]];
				cout << "Win contribution: " << tmp_card_stat.win_contribution << endl;
				cout << "Eval: " << tmp_card_stat.eval << endl << endl;
				cout << "Card: " << endl;
				tmp_card = GenerateSingleCard(seed_list[card_indices[r + card_ref_index]]);
				cout << GetCardDetail(tmp_card) << endl << endl;
				cout << "Input any character to continue." << endl;
				cin >> ch;
				DeleteCard(tmp_card);
			}

			// sort according to the stats of decks
			vector<int> deck_indices(deck_pool_size);
			SortStatInIndices(deck_stats, deck_indices);
			MatchStat tmp_deck_stat;
			vector<int> tmp_deck_seeds(n);
			vector<Card*> tmp_deck_cards;
			int deck_ref_index;

			// top decks
			deck_ref_index = -1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Top Deck #" << r << ":" << endl << endl;
				tmp_deck_stat = deck_stats[deck_indices[r + deck_ref_index]];
				cout << "Wins: " << tmp_deck_stat.win_contribution << endl;
				cout << "Eval: " << tmp_deck_stat.eval << endl << endl;
				cout << "Cards: " << endl;
				for (int i = 0; i < n; i++) // index to seeds
					tmp_deck_seeds[i] = seed_list[deck_list[deck_indices[r + deck_ref_index]][i]];
				tmp_deck_cards = GenerateRandDeckFromSeedList(tmp_deck_seeds);
				for (int i = 0; i < n; i++)
					cout << i << ": " << GetCardBrief(tmp_deck_cards[i]) << endl;
				cout << endl;
				while (true)
				{
					int i;
					cout << "Input card index to view detail (input illegal index to skip): ";
					cin >> i;
					if (i < 0 || i >= n)
						break;
					cout << endl << GetCardDetail(tmp_deck_cards[i]) << endl;
				}
				for (int i = 0; i < n; i++)
					DeleteCard(tmp_deck_cards[i]);
			}

			// middle decks
			deck_ref_index = (deck_pool_size - display_num) / 2 - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Middle Deck #" << r << ":" << endl << endl;
				tmp_deck_stat = deck_stats[deck_indices[r + deck_ref_index]];
				cout << "Wins: " << tmp_deck_stat.win_contribution << endl;
				cout << "Eval: " << tmp_deck_stat.eval << endl << endl;
				cout << "Cards: " << endl;
				for (int i = 0; i < n; i++) // index to seeds
					tmp_deck_seeds[i] = seed_list[deck_list[deck_indices[r + deck_ref_index]][i]];
				tmp_deck_cards = GenerateRandDeckFromSeedList(tmp_deck_seeds);
				for (int i = 0; i < n; i++)
					cout << i << ": " << GetCardBrief(tmp_deck_cards[i]) << endl;
				cout << endl;
				while (true)
				{
					int i;
					cout << "Input card index to view detail (input illegal index to skip): ";
					cin >> i;
					if (i < 0 || i >= n)
						break;
					cout << endl << GetCardDetail(tmp_deck_cards[i]) << endl;
				}
				for (int i = 0; i < n; i++)
					DeleteCard(tmp_deck_cards[i]);
			}

			// bottom decks
			deck_ref_index = deck_pool_size - display_num - 1;
			for (int r = 1; r <= display_num; r++)
			{
				cout << "Bottom Deck #" << r << ":" << endl << endl;
				tmp_deck_stat = deck_stats[deck_indices[r + deck_ref_index]];
				cout << "Wins: " << tmp_deck_stat.win_contribution << endl;
				cout << "Eval: " << tmp_deck_stat.eval << endl << endl;
				cout << "Cards: " << endl;
				for (int i = 0; i < n; i++) // index to seeds
					tmp_deck_seeds[i] = seed_list[deck_list[deck_indices[r + deck_ref_index]][i]];
				tmp_deck_cards = GenerateRandDeckFromSeedList(tmp_deck_seeds);
				for (int i = 0; i < n; i++)
					cout << i << ": " << GetCardBrief(tmp_deck_cards[i]) << endl;
				cout << endl;
				while (true)
				{
					int i;
					cout << "Input card index to view detail (input illegal index to skip): ";
					cin >> i;
					if (i < 0 || i >= n)
						break;
					cout << endl << GetCardDetail(tmp_deck_cards[i]) << endl;
				}
				for (int i = 0; i < n; i++)
					DeleteCard(tmp_deck_cards[i]);
			}*/
		}
		break;
	case 3:
		while (ch == 'y' || ch == 'Y')
		{
			cout << "Input Seed (negative to set with the time) " << endl;
			cin >> seed;
			if (seed < 0)
				seed = time(NULL);
			vector<Card*> deck1 = GenerateRandDeck(n, seed);

			seed += 17; // just some random stuff
			vector<Card*> deck2 = GenerateRandDeck(n, seed);

			cout << "Input AI level - 0: Pure Random; 1 ~ 9: Search Based (higher number does more trials)" << endl;
			unsigned ai_level;
			cin >> ai_level;

			queue<DeferredEvent*> event_queue;
			Player human_player("Player", 30, deck1, false, event_queue);
			Player ai_player("AI", 30, deck2, true, event_queue, ai_level);

			human_player.opponent = &ai_player;
			ai_player.opponent = &human_player;

			human_player.SetAllCardAfflications();
			ai_player.SetAllCardAfflications();

			Player* player1;
			Player* player2;

			DecidePlayOrder(&human_player, &ai_player, player1, player2);			

			cout << "Game Begins." << endl;
			cout << "Input H for help on commands" << endl;

			player1->InitialCardDraw(false);
			player2->InitialCardDraw(true);

			while (true)
			{
				player1->StartTurn();
				(player1->*(player1->input_func))();
				if (player1->CheckLose() || player2->CheckLose())
					break;

				player2->StartTurn();
				(player2->*(player2->input_func))();
				if (player1->CheckLose() || player2->CheckLose())
					break;
			}

			if (player1->CheckLose())
			{
				if (player2->CheckLose())
					cout << "It is a Draw." << endl;
				else
					cout << player2->name << " Won." << endl;
			}
			else
				cout << player1->name << " Won." << endl;

			cout << "Game Ends." << endl;

			while (!event_queue.empty())
			{
				delete event_queue.front();  // note: this is not deleting the actual card but the entity for flagging
				event_queue.pop();
			}

			cout << "Continue? (y/n)" << endl;
			cin >> ch;
		}
		break;
	case 2:
		while (seed >= 0)
		{
			cout << "Input Seed (negative to quit) for Deck 1" << endl;
			cin >> seed;
			if (seed < 0)
				break;
			vector<Card*> deck1 = GenerateRandDeck(n, seed);

			cout << "Input Seed (negative to quit) for Deck 2" << endl;
			cin >> seed;
			if (seed < 0)
				break;
			vector<Card*> deck2 = GenerateRandDeck(n, seed);

			queue<DeferredEvent*> event_queue;
			Player player1("Player1", 30, deck1, false, event_queue);
			Player player2("Player2", 30, deck2, false, event_queue);

			player1.opponent = &player2;
			player2.opponent = &player1;

			player1.SetAllCardAfflications();
			player2.SetAllCardAfflications();

			cout << "Game Begins." << endl;
			cout << "Input H for help on commands" << endl;

			player1.InitialCardDraw(false);
			player2.InitialCardDraw(true);

			while (true)
			{
				player1.StartTurn();
				player1.TakeInputs();
				if (player1.CheckLose() || player2.CheckLose())
					break;

				player2.StartTurn();
				player2.TakeInputs();
				if (player1.CheckLose() || player2.CheckLose())
					break;
			}

			if (player1.CheckLose())
			{
				if (player2.CheckLose())
					cout << "It is a Draw." << endl;
				else
					cout << "Player 2 Won." << endl;
			}
			else
				cout << "Player 1 Won." << endl;

			cout << "Game Ends." << endl;

			while (!event_queue.empty())
			{
				delete event_queue.front();  // note: this is not deleting the actual card but the entity for flagging
				event_queue.pop();
			}
		}
		break;
	case 1:
		while (seed >= 0)
		{
			cout << "Input Seed (negative to quit)" << endl;
			cin >> seed;
			if (seed < 0)
				break;

			Card* card = GenerateSingleCard(seed);
			cout << endl << GetCardDetail(card) << endl;
			DeleteCard(card);
		}
		break;
	default:
		seed = time(NULL);
		while (ch == 'y' || ch == 'Y')
		{
			Card* card = GenerateSingleCard(seed);
			cout << endl << GetCardDetail(card) << endl;
			DeleteCard(card);

			cout << "Continue? (y/n)" << endl;
			cin >> ch;
			seed = GetGiglRandInt();
		}
	}

	return 0;
}
