#include "animation/state_machine_input.hpp"
#include "importers/import_stack.hpp"
#include "importers/state_machine_importer.hpp"
#include "generated/animation/state_machine_base.hpp"

using namespace rive;

StatusCode StateMachineInput::onAddedDirty(CoreContext* context)
{
	return StatusCode::Ok;
}

StatusCode StateMachineInput::onAddedClean(CoreContext* context)
{
	return StatusCode::Ok;
}

StatusCode StateMachineInput::import(ImportStack& importStack)
{
	auto stateMachineImporter =
	    importStack.latest<StateMachineImporter>(StateMachineBase::typeKey);
	if (stateMachineImporter == nullptr)
	{
		return StatusCode::MissingObject;
	}
	stateMachineImporter->addInput(this);
	return Super::import(importStack);
}