import unittest
from uuid import UUID
from driftlab.calibration import compare
from driftlab.calibration_schema import SCHEMA,CALIBRATION_APP_ID,PRODUCTION_APP_ID
from fit_fixtures import decode_fixture


class ProvenanceTests(unittest.TestCase):
    def report(self, **kwargs):
        samples,quality,messages=decode_fixture(**kwargs)
        return compare(samples,messages,quality)

    def test_complete_calibration_contract(self):
        self.assertEqual(self.report()['status'],'matched_candidate')
    def test_production_and_unknown_uuid_rejected(self):
        for app in (PRODUCTION_APP_ID,'01'*16):
            with self.subTest(app=app):
                self.assertEqual(self.report(apps=(app,))['status'],'unsupported')
    def test_guid_little_endian_layout(self):
        raw=UUID(hex=CALIBRATION_APP_ID).bytes_le.hex()
        self.assertEqual(self.report(apps=(raw,))['status'],'matched_candidate')
    def test_missing_provenance_rejected(self):
        samples,quality,messages=decode_fixture()
        for message in messages:
            message.pop('developer_fields',None)
        self.assertEqual(compare(samples,messages,quality)['status'],'unsupported')
    def test_both_producers_and_duplicate_names_preserved(self):
        samples,quality,messages=decode_fixture(apps=(CALIBRATION_APP_ID,PRODUCTION_APP_ID))
        record=next(m for m in messages if m['type']=='record')
        fields=[f for f in record['developer_fields'] if f['name']=='dg_steady']
        self.assertEqual(len(fields),2)
        self.assertEqual({f['application_id'] for f in fields},{CALIBRATION_APP_ID,PRODUCTION_APP_ID})
        self.assertNotIn('dg_steady',record['fields'])
        self.assertEqual(compare(samples,messages,quality)['status'],'unsupported')
    def test_each_required_definition_missing(self):
        for name in SCHEMA:
            with self.subTest(name=name):
                self.assertEqual(self.report(omit=(name,))['status'],'incomplete')
    def test_wrong_type_size_id_and_message(self):
        for replacement in (('record',10,0x86,4),('record',10,0x84,4),
                            ('record',24,0x84,2),('session',10,0x84,2)):
            with self.subTest(definition=replacement):
                self.assertEqual(self.report(override={'dg_minute_seq':replacement})['status'],'unsupported')
    def test_duplicate_same_producer_rejected(self):
        self.assertEqual(self.report(duplicate=True)['status'],'unsupported')
    def test_integer_difference_is_mismatch(self):
        self.assertEqual(self.report(delta={'dg_min_power_sum':1})['status'],'mismatch')
    def test_missing_integer_values_are_incomplete(self):
        for name in ('dg_sample_seq','dg_ride_state_final','dg_bucket_width'):
            with self.subTest(name=name):
                self.assertEqual(self.report(null=(name,))['status'],'incomplete')
    def test_nullable_stale_floats_allowed(self):
        self.assertEqual(self.report(null=('dg_ride_drift','dg_ride_drift_final','dg_power_change'))['status'],
                         'matched_candidate')
    def test_meaningful_session_float_missing(self):
        self.assertEqual(self.report(null=('dg_compat_drift',))['status'],'incomplete')
    def test_sequence_gaps_and_conflicts_incomplete(self):
        self.assertEqual(self.report(sequence_gap=True)['status'],'incomplete')
        self.assertEqual(self.report(conflict=True)['status'],'incomplete')

    def test_two_calibration_indices_ambiguous(self):
        self.assertEqual(self.report(apps=(CALIBRATION_APP_ID,CALIBRATION_APP_ID))['status'],'unsupported')
    def test_definition_exists_but_message_field_missing(self):
        for kind,name in (('record','dg_ef'),('session','dg_bucket_width')):
            samples,quality,messages=decode_fixture()
            message=next(m for m in messages if m['type']==kind)
            message['developer_fields']=[f for f in message['developer_fields'] if f['name']!=name]
            self.assertEqual(compare(samples,messages,quality)['status'],'incomplete')
    def test_source_identity_redefinition_rejected(self):
        samples,quality,messages=decode_fixture()
        messages.append(dict(type='developer_identity_conflict',fields={'index':0}))
        self.assertEqual(compare(samples,messages,quality)['status'],'unsupported')
    def test_state_difference_not_hidden_by_float_tolerance(self):
        self.assertEqual(self.report(delta={'dg_ride_state':1})['status'],'mismatch')
    def test_missing_ef_value_is_incomplete(self):
        self.assertEqual(self.report(null=('dg_ef',))['status'],'incomplete')
