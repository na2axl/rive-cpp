#include "animation/transition_bool_condition.hpp"
#include "animation/state_transition.hpp"
#include "importers/state_transition_importer.hpp"
#include "importers/state_machine_importer.hpp"
#include "animation/state_machine.hpp"

using namespace rive;

StatusCode TransitionCondition::onAddedDirty(CoreContext* context)
{
	return StatusCode::Ok;
}

StatusCode TransitionCondition::onAddedClean(CoreContext* context)
{
	return StatusCode::Ok;
}

StatusCode TransitionCondition::import(ImportStack& importStack)
{
	auto stateMachineImporter =
	    importStack.latest<StateMachineImporter>(StateMachine::typeKey);
	if (stateMachineImporter == nullptr)
	{
		return StatusCode::MissingObject;
	}

	// Make sure the inputId doesn't overflow the input buffer.
	if (inputId() < 0 ||
	    inputId() >= stateMachineImporter->stateMachine()->inputCount())
	{
		return StatusCode::InvalidObject;
	}
	if (!validateInputType(
	        stateMachineImporter->stateMachine()->input((size_t)inputId())))
	{
		return StatusCode::InvalidObject;
	}

	auto transitionImporter =
	    importStack.latest<StateTransitionImporter>(StateTransition::typeKey);
	if (transitionImporter == nullptr)
	{
		return StatusCode::MissingObject;
	}
	transitionImporter->addCondition(this);
	return Super::import(importStack);
}