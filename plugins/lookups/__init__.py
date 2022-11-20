import sys
import traceback

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.module_utils.common.text.converters import jsonify
from ansible.module_utils.six import ( PY2 )
from ansible.module_utils.common._collections_compat import (
    KeysView,
    Mapping,
    Sequence
)
from ansible.module_utils.common.parameters import (
    remove_values
)
from ansible.module_utils.common.warnings import ( get_warning_messages, deprecate, get_deprecation_messages, warn )

SEQUENCETYPE = frozenset, KeysView, Sequence

class MinimalModule():
    def __init__():
        self.ansible_version = ''

        def jsonify(self, data):
            try:
                return jsonify(data)
            except UnicodeError as e:
                self.fail_json(msg=to_text(e))

    def fail_json(self, msg, **kwargs):
        ''' return from the module, with an error message '''

        kwargs['failed'] = True
        kwargs['msg'] = msg

        # Add traceback if debug or high verbosity and it is missing
        # NOTE: Badly named as exception, it really always has been a traceback
        if 'exception' not in kwargs and sys.exc_info()[2] and (self._debug or self._verbosity >= 3):
            if PY2:
                # On Python 2 this is the last (stack frame) exception and as such may be unrelated to the failure
                kwargs['exception'] = 'WARNING: The below traceback may *not* be related to the actual failure.\n' +\
                                      ''.join(traceback.format_tb(sys.exc_info()[2]))
            else:
                kwargs['exception'] = ''.join(traceback.format_tb(sys.exc_info()[2]))

        self._return_formatted(kwargs)
        sys.exit(1)

    def _return_formatted(self, kwargs):
        if 'invocation' not in kwargs:
            kwargs['invocation'] = {'module_args': self.params}

        if 'warnings' in kwargs:
            if isinstance(kwargs['warnings'], list):
                for w in kwargs['warnings']:
                    self.warn(w)
            else:
                self.warn(kwargs['warnings'])

        warnings = get_warning_messages()
        if warnings:
            kwargs['warnings'] = warnings

        if 'deprecations' in kwargs:
            if isinstance(kwargs['deprecations'], list):
                for d in kwargs['deprecations']:
                    if isinstance(d, SEQUENCETYPE) and len(d) == 2:
                        self.deprecate(d[0], version=d[1])
                    elif isinstance(d, Mapping):
                        self.deprecate(d['msg'], version=d.get('version'), date=d.get('date'),
                                       collection_name=d.get('collection_name'))
                    else:
                        self.deprecate(d)  # pylint: disable=ansible-deprecated-no-version
            else:
                self.deprecate(kwargs['deprecations'])  # pylint: disable=ansible-deprecated-no-version

        deprecations = get_deprecation_messages()
        if deprecations:
            kwargs['deprecations'] = deprecations

        kwargs = remove_values(kwargs, self.no_log_values)
        print('\n%s' % self.jsonify(kwargs))

    def deprecate(self, msg, version=None, date=None, collection_name=None):
        if version is not None and date is not None:
            raise AssertionError("implementation error -- version and date must not both be set")
        deprecate(msg, version=version, date=date, collection_name=collection_name)
        # For compatibility, we accept that neither version nor date is set,
        # and treat that the same as if version would haven been set
        if date is not None:
            self.log('[DEPRECATION WARNING] %s %s' % (msg, date))
        else:
            self.log('[DEPRECATION WARNING] %s %s' % (msg, version))
