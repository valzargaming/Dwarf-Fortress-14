/// -- Plant backfire element --
/// Certain high-danger plants, like death-nettles, will backfire and harm the holder if they're not properly protected.
/// If a user is protected with something like leather gloves, they can handle them normally.
/// If they're not protected properly, we invoke a callback on the user, harming or inconveniencing them.
/datum/element/plant_backfire
	element_flags = ELEMENT_BESPOKE | ELEMENT_DETACH
	id_arg_index = 2
	/// Whether we stop the current action if backfire is triggered (EX: returning CANCEL_ATTACK_CHAIN)
	var/cancel_action = FALSE
	/// The callback of the backfire effect of the plant.
	var/datum/callback/backfire_callback
	/// Any extra traits we want to check in addition to TRAIT_PLANT_SAFE. Mobs with a trait in this list will be considered safe. List of traits.
	var/extra_traits
	/// Any plant genes we want to check that are required for our plant to be dangerous. Plants without a gene in this list will be considered safe. List of typepaths.
	var/extra_genes

/datum/element/plant_backfire/Attach(datum/target, backfire_callback, cancel_action = FALSE, extra_traits, extra_genes)
	. = ..()
	if(!isitem(target))
		return ELEMENT_INCOMPATIBLE

	src.cancel_action = cancel_action
	src.extra_traits = extra_traits
	src.extra_genes = extra_genes
	src.backfire_callback = backfire_callback

	RegisterSignal(target, COMSIG_ITEM_PRE_ATTACK, PROC_REF(attack_safety_check))
	RegisterSignal(target, COMSIG_ITEM_PICKUP, PROC_REF(pickup_safety_check))
	RegisterSignal(target, COMSIG_MOVABLE_PRE_THROW, PROC_REF(throw_safety_check))

/datum/element/plant_backfire/Detach(datum/target)
	. = ..()
	UnregisterSignal(target, list(COMSIG_ITEM_PRE_ATTACK, COMSIG_ITEM_PICKUP, COMSIG_MOVABLE_PRE_THROW))

/*
 * Checks before we attack if we're okay to continue.
 *
 * source - our plant
 * user - the mob wielding our [source]
 */
/datum/element/plant_backfire/proc/attack_safety_check(datum/source, atom/target, mob/user)
	SIGNAL_HANDLER

	if(plant_safety_check(source, user))
		return
	backfire_callback.Invoke(source, user)
	if(cancel_action)
		return COMPONENT_CANCEL_ATTACK_CHAIN

/*
 * Checks before we pick up the plant if we're okay to continue.
 *
 * source - our plant
 * user - the mob picking our [source]
 */
/datum/element/plant_backfire/proc/pickup_safety_check(datum/source, mob/user)
	SIGNAL_HANDLER

	if(plant_safety_check(source, user))
		return
	backfire_callback.Invoke(source, user)

/*
 * Checks before we throw the plant if we're okay to continue.
 *
 * source - our plant
 * thrower - the mob throwing our [source]
 */
/datum/element/plant_backfire/proc/throw_safety_check(datum/source, list/arguments)
	SIGNAL_HANDLER

	var/mob/living/thrower = arguments[4] // 4th arg = mob/thrower
	if(plant_safety_check(source, thrower))
		return
	backfire_callback.Invoke(source, thrower)
	if(cancel_action)
		return COMPONENT_CANCEL_THROW

/*
 * Actually checks if our user is safely handling our plant.
 *
 * Checks for TRAIT_PLANT_SAFE, and returns TRUE if we have it.
 * Then, any extra traits we need to check (Like TRAIT_PIERCEIMMUNE for nettles) and returns TRUE if we have one of them.
 * Then, any extra genes we need to check (Like liquid contents for bluespace tomatos) and returns TRUE if we don't have the gene.
 *
 * source - our plant
 * user - the carbon handling our [source]
 *
 * returns FALSE if none of the checks are successful.
 */
/datum/element/plant_backfire/proc/plant_safety_check(datum/source, mob/living/carbon/user)
	if(!istype(user))
		return TRUE

	if(HAS_TRAIT(user, TRAIT_PLANT_SAFE))
		return TRUE

	for(var/checked_trait in extra_traits)
		if(HAS_TRAIT(user, checked_trait))
			return TRUE

	return FALSE
