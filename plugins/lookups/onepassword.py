from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = '''
    name: onepassword
    author: 
        - Chris Schmidt(@chrisisbeef)
        - 1Password (@1Password)
    version_added: ''
    short_description: Returns the value of an item from onepassword
    description:
    options:
        _terms:
            description: List of onepassword coordinates to lookup (vault/item/field)
        section:
            type: str
            description:
            - An item section label or ID.
            - If provided, the module limits the search for the field to this section.
            - If not provided, the module searches the entire item for the field.

    extends_documentation_fragment:
        - onepassword.connect.api_params
'''

EXAMPLES = '''
---
- name: Get the value of a field labeled "username" in an item named "MySQL Database" in a vault named "Automation"
  ansible.builtin.debug:
    var: lookup('onepassword', 'Automation/MySQL Database/username')

- name: Get the value of a field labeled "username" under the section "Credentials" in an item named "MySQL Database" in a vault named "Automation"
  ansible.builtin.debug:
    var: lookup('onepassword', 'Automation/MySQL Database/username', section='Credentials')
'''

RETURN = '''
_raw:
    description:
        - value of the secret from the onepassword connect server
    type: str
'''

import sys
import traceback

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.module_utils.basic import AnsibleModule, env_fallback

from ansible_collections.onepassword.connect.plugins.module_utils import specs, api, errors, fields, util
from ansible_collections.onepassword.connect.plugins.module_utils.api import OnePassword
from ansible_collections.onepassword.connect.lookups import MinimalModule

class OnePasswordLookupModule(LookupBase):
    def find_field(self, field_identifier, item, section=None) -> dict:
        """
        Tries to find the requested field within the provided item.

        The field may be a valid client UUID or it may be the field's label.
        If the section kwarg is provided, the function limits its search
        to fields within that section.
        """
        if not item.get("fields"):
            raise errors.NotFoundError("Item has no fields")

        section_uuid = None
        if section:
            section_uuid = self._get_section_uuid(item.get("sections"), section)

        if api.valid_client_uuid(field_identifier):
            return self._find_field_by_id(field_identifier, item["fields"], section_uuid)

        return self._find_field_by_label(field_identifier, item["fields"], section_uuid)

    def _find_field_by_id(self, field_id, fields, section_id=None):
        for field in fields:

            if section_id is None and field["id"] == field_id:
                return field

            if field.get("section", {}).get("id") == section_id \
                    and field["id"] == field_id:
                return field

        raise errors.NotFoundError("Field not found in item")

    def _find_field_by_label(self, field_label, fields, section_id=None):
        wanted_label = util.utf8_normalize(field_label)

        for field in fields:
            label = util.utf8_normalize(field["label"])
            if section_id is None and label == wanted_label:
                return field

            if field.get("section", {}).get("id") == section_id \
                    and label == wanted_label:
                return field

        raise errors.NotFoundError("Field with provided label not found in item")

    def _get_section_uuid(self, sections, section_identifier):
        if not sections:
            return None

        if not api.valid_client_uuid(section_identifier):
            return self._find_section_id_by_label(sections, section_identifier)
        return section_identifier

    def _find_section_id_by_label(self, sections, label):
        label = util.utf8_normalize(label)

        for section in sections:
            if util.utf8_normalize(section["label"]) == label:
                return section["id"]

        raise errors.NotFoundError("Section label not found in item")

    def run(self, terms, variables=None, **kwargs):
        self.set_options(var_options=variables, direct=kwargs)

        if len(terms) > 1:
            raise errors.Error(message="OnePassword does not support multiple lookups")

        api_client = OnePassword(
            hostname=self.get_option('hostname') or env_fallback(['OP_CONNECT_HOST']),
            token=self.get_option('token') or env_fallback(['OP_CONNECT_TOKEN']),
            module=MinimalModule()
        )

        section = self.get_option('section') or None

        terms_split = terms[0].split("/")

        if len(terms_split) < 3:
            raise errors.Error("Secret coordinate must follow the pattern <vault>/<item>/<field>. Got " + terms[0])

        vault = terms_split[0]
        item  = terms_split[1]
        field = terms_split[2]

        if not api.valid_client_uuid(vault):
            vault = api_client.get_vault_id_by_name(vault)

        if not api.valid_client_uuid(item):
            item_info = api_client.get_item_by_name(item, vault)
        else:
            item_info = api_client.get_item_by_id(item, vault)
        
        field_info = self.find_field(field, item_info, section=section)

        return field_info.value
