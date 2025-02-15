#include "component.hpp"
#include "artboard.hpp"
#include "container_component.hpp"
#include "core_context.hpp"
#include "importers/artboard_importer.hpp"
#include "importers/import_stack.hpp"
#include <algorithm>

using namespace rive;

StatusCode Component::onAddedDirty(CoreContext* context)
{
	m_Artboard = static_cast<Artboard*>(context);
	if (this == m_Artboard)
	{
		// We're the artboard, don't parent to ourselves.
		return StatusCode::Ok;
	}
	auto coreObject = context->resolve(parentId());
	if (coreObject == nullptr || !coreObject->is<ContainerComponent>())
	{
		return StatusCode::MissingObject;
	}
	m_Parent = reinterpret_cast<ContainerComponent*>(coreObject);
	return StatusCode::Ok;
}

void Component::addDependent(Component* component)
{
	// Make it's not already a dependent.
	assert(std::find(m_Dependents.begin(), m_Dependents.end(), component) ==
	       m_Dependents.end());
	m_Dependents.push_back(component);
}

bool Component::addDirt(ComponentDirt value, bool recurse)
{
	if ((m_Dirt & value) == value)
	{
		// Already marked.
		return false;
	}

	// Make sure dirt is set before calling anything that can set more dirt.
	m_Dirt |= value;

	onDirty(m_Dirt);

	m_Artboard->onComponentDirty(this);

	if (!recurse)
	{
		return true;
	}

	for (auto d : m_Dependents)
	{
		d->addDirt(value, true);
	}
	return true;
}

StatusCode Component::import(ImportStack& importStack)
{
	auto artboardImporter =
	    importStack.latest<ArtboardImporter>(ArtboardBase::typeKey);
	if (artboardImporter == nullptr)
	{
		return StatusCode::MissingObject;
	}
	artboardImporter->addComponent(this);
	return Super::import(importStack);
}