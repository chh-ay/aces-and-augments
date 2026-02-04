# poker_hand_evaluator.gd
# Core system for evaluating poker hands in Aces & Augments
# Place in: res://scripts/systems/poker_hand_evaluator.gd

class_name PokerHandEvaluator
extends RefCounted

## Poker hand rankings from lowest to highest
enum HandRank {
	HIGH_CARD = 0,
	PAIR = 1,
	TWO_PAIR = 2,
	THREE_OF_A_KIND = 3,
	STRAIGHT = 4,
	FLUSH = 5,
	FULL_HOUSE = 6,
	FOUR_OF_A_KIND = 7,
	STRAIGHT_FLUSH = 8,
	ROYAL_FLUSH = 9
}

## Hand rank names for display
const HAND_NAMES: Dictionary = {
	HandRank.HIGH_CARD: "High Card",
	HandRank.PAIR: "Pair",
	HandRank.TWO_PAIR: "Two Pair",
	HandRank.THREE_OF_A_KIND: "Three of a Kind",
	HandRank.STRAIGHT: "Straight",
	HandRank.FLUSH: "Flush",
	HandRank.FULL_HOUSE: "Full House",
	HandRank.FOUR_OF_A_KIND: "Four of a Kind",
	HandRank.STRAIGHT_FLUSH: "Straight Flush",
	HandRank.ROYAL_FLUSH: "Royal Flush"
}

## Augment power multipliers per hand rank
const AUGMENT_POWER: Dictionary = {
	HandRank.HIGH_CARD: 1.05,        # +5%
	HandRank.PAIR: 1.10,             # +10%
	HandRank.TWO_PAIR: 1.15,         # +15%
	HandRank.THREE_OF_A_KIND: 1.20,  # +20%
	HandRank.STRAIGHT: 1.25,         # +25%
	HandRank.FLUSH: 1.25,            # +25%
	HandRank.FULL_HOUSE: 1.30,       # +30%
	HandRank.FOUR_OF_A_KIND: 1.35,   # +35%
	HandRank.STRAIGHT_FLUSH: 1.40,   # +40%
	HandRank.ROYAL_FLUSH: 2.00       # +100% (also triggers good ending)
}

## Enemy mutation multipliers (weaker than augments)
const MUTATION_POWER: Dictionary = {
	HandRank.HIGH_CARD: 1.02,        # +2%
	HandRank.PAIR: 1.05,             # +5%
	HandRank.TWO_PAIR: 1.07,         # +7%
	HandRank.THREE_OF_A_KIND: 1.10,  # +10%
	HandRank.STRAIGHT: 1.12,         # +12%
	HandRank.FLUSH: 1.12,            # +12%
	HandRank.FULL_HOUSE: 1.15,       # +15%
	HandRank.FOUR_OF_A_KIND: 1.17,   # +17%
	HandRank.STRAIGHT_FLUSH: 1.20,   # +20%
	HandRank.ROYAL_FLUSH: 1.25       # +25%
}


## Represents a single playing card
class Card:
	var suit: String   # "hearts", "diamonds", "clubs", "spades"
	var value: int     # 1=Ace, 2-10, 11=Jack, 12=Queen, 13=King

	func _init(p_suit: String, p_value: int) -> void:
		suit = p_suit
		value = p_value

	func get_display_value() -> String:
		match value:
			1: return "A"
			11: return "J"
			12: return "Q"
			13: return "K"
			_: return str(value)

	func get_display_name() -> String:
		return "%s of %s" % [get_display_value(), suit.capitalize()]


## Result of hand evaluation
class HandResult:
	var rank: HandRank
	var name: String
	var augment_multiplier: float
	var mutation_multiplier: float
	var is_royal_flush: bool
	var cards: Array  # The 5 cards evaluated

	func _init(p_rank: HandRank, p_cards: Array) -> void:
		rank = p_rank
		name = HAND_NAMES[p_rank]
		augment_multiplier = AUGMENT_POWER[p_rank]
		mutation_multiplier = MUTATION_POWER[p_rank]
		is_royal_flush = (p_rank == HandRank.ROYAL_FLUSH)
		cards = p_cards


## Evaluate a hand of exactly 5 cards
## Returns HandResult with rank and multipliers
static func evaluate_hand(cards: Array) -> HandResult:
	assert(cards.size() == 5, "Hand must contain exactly 5 cards")

	# Sort cards by value for easier evaluation
	var sorted_cards: Array = cards.duplicate()
	sorted_cards.sort_custom(func(a, b): return a.value < b.value)

	# Check for flush (all same suit)
	var is_flush: bool = _is_flush(sorted_cards)

	# Check for straight (5 consecutive values)
	var is_straight: bool = _is_straight(sorted_cards)

	# Count value occurrences
	var value_counts: Dictionary = _count_values(sorted_cards)
	var counts: Array = value_counts.values()
	counts.sort()
	counts.reverse()  # Highest counts first

	# Determine hand rank
	var rank: HandRank

	# Royal Flush: A-10-J-Q-K of same suit
	if is_flush and is_straight and _is_royal(sorted_cards):
		rank = HandRank.ROYAL_FLUSH
	# Straight Flush: 5 consecutive same suit
	elif is_flush and is_straight:
		rank = HandRank.STRAIGHT_FLUSH
	# Four of a Kind: 4 same value
	elif counts[0] == 4:
		rank = HandRank.FOUR_OF_A_KIND
	# Full House: 3 same + 2 same
	elif counts[0] == 3 and counts[1] == 2:
		rank = HandRank.FULL_HOUSE
	# Flush: 5 same suit
	elif is_flush:
		rank = HandRank.FLUSH
	# Straight: 5 consecutive
	elif is_straight:
		rank = HandRank.STRAIGHT
	# Three of a Kind: 3 same value
	elif counts[0] == 3:
		rank = HandRank.THREE_OF_A_KIND
	# Two Pair: 2 same + 2 same
	elif counts[0] == 2 and counts[1] == 2:
		rank = HandRank.TWO_PAIR
	# Pair: 2 same value
	elif counts[0] == 2:
		rank = HandRank.PAIR
	# High Card: nothing
	else:
		rank = HandRank.HIGH_CARD

	return HandResult.new(rank, cards)


## Check if all cards have the same suit
static func _is_flush(cards: Array) -> bool:
	var first_suit: String = cards[0].suit
	for card in cards:
		if card.suit != first_suit:
			return false
	return true


## Check if cards form a straight (5 consecutive values)
## Handles Ace-low straight (A-2-3-4-5)
static func _is_straight(cards: Array) -> bool:
	var values: Array = []
	for card in cards:
		values.append(card.value)
	values.sort()

	# Check normal straight
	var is_normal_straight: bool = true
	for i in range(1, values.size()):
		if values[i] != values[i - 1] + 1:
			is_normal_straight = false
			break

	if is_normal_straight:
		return true

	# Check Ace-low straight (A-2-3-4-5)
	# Ace is value 1, so sorted would be [1, 2, 3, 4, 5]
	if values == [1, 2, 3, 4, 5]:
		return true

	# Check Ace-high straight (10-J-Q-K-A)
	# Values: [1, 10, 11, 12, 13]
	if values == [1, 10, 11, 12, 13]:
		return true

	return false


## Check if cards form a royal straight (10-J-Q-K-A)
static func _is_royal(cards: Array) -> bool:
	var values: Array = []
	for card in cards:
		values.append(card.value)
	values.sort()
	return values == [1, 10, 11, 12, 13]


## Count occurrences of each card value
static func _count_values(cards: Array) -> Dictionary:
	var counts: Dictionary = {}
	for card in cards:
		if card.value in counts:
			counts[card.value] += 1
		else:
			counts[card.value] = 1
	return counts


## Create a standard 52-card deck
static func create_deck() -> Array:
	var deck: Array = []
	var suits: Array = ["hearts", "diamonds", "clubs", "spades"]

	for suit in suits:
		for value in range(1, 14):  # 1 (Ace) to 13 (King)
			deck.append(Card.new(suit, value))

	return deck


## Shuffle a deck using Fisher-Yates algorithm
static func shuffle_deck(deck: Array) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp


## Draw n cards from the deck (removes them from deck)
static func draw_cards(deck: Array, count: int) -> Array:
	var drawn: Array = []
	for i in range(min(count, deck.size())):
		drawn.append(deck.pop_front())
	return drawn


# =============================================================================
# USAGE EXAMPLE (for testing)
# =============================================================================
#
# func _ready() -> void:
#     # Create and shuffle deck
#     var deck: Array = PokerHandEvaluator.create_deck()
#     PokerHandEvaluator.shuffle_deck(deck)
#
#     # Draw 5 cards
#     var hand: Array = PokerHandEvaluator.draw_cards(deck, 5)
#
#     # Evaluate the hand
#     var result: PokerHandEvaluator.HandResult = PokerHandEvaluator.evaluate_hand(hand)
#
#     print("Hand: ", result.name)
#     print("Augment Multiplier: ", result.augment_multiplier)
#     print("Mutation Multiplier: ", result.mutation_multiplier)
#     print("Is Royal Flush: ", result.is_royal_flush)
#
#     # Print each card
#     for card in result.cards:
#         print("  - ", card.get_display_name())
#
# =============================================================================
# TEST SPECIFIC HANDS
# =============================================================================
#
# func test_royal_flush() -> void:
#     var cards: Array = [
#         PokerHandEvaluator.Card.new("spades", 1),   # Ace
#         PokerHandEvaluator.Card.new("spades", 10),  # 10
#         PokerHandEvaluator.Card.new("spades", 11),  # Jack
#         PokerHandEvaluator.Card.new("spades", 12),  # Queen
#         PokerHandEvaluator.Card.new("spades", 13),  # King
#     ]
#     var result = PokerHandEvaluator.evaluate_hand(cards)
#     assert(result.rank == PokerHandEvaluator.HandRank.ROYAL_FLUSH)
#     print("Royal Flush test passed!")
