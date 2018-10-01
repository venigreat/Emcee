import os
import unittest
import json
from xml.etree import ElementTree


def check_file_exists(path):
    if not os.path.exists(path):
        raise AssertionError("Expected to have file at: {path}".format(path=path))


def get_test_cases_from_xml_file(path):
    tree = ElementTree.parse(path)
    root = tree.getroot()
    cases = []
    for case in root.findall('.//testcase'):
        if not case.findall('skipped'):
            case_dict = case.attrib.copy()
            if len(case):
                for child in case:
                    print("child: " + str(child))
                    case_dict[child.tag] = child.attrib.copy()
            cases.append(case_dict)
    return cases


class IntegrationTests(unittest.TestCase):
    @staticmethod
    def test_check_reports_exist():
        check_file_exists("auxiliary/tempfolder/test-results/iphone_se_ios_103.json")
        check_file_exists("auxiliary/tempfolder/test-results/iphone_se_ios_103.xml")
        check_file_exists("auxiliary/tempfolder/test-results/trace.combined.json")
        check_file_exists("auxiliary/tempfolder/test-results/junit.combined.xml")

    def test_junit_contents(self):
        iphone_se_junit = get_test_cases_from_xml_file("auxiliary/tempfolder/test-results/iphone_se_ios_103.xml")
        self.assertEqual(len(iphone_se_junit), 5)

        successful_tests = set([item["name"] for item in iphone_se_junit if item.get("failure") is None])
        failed_tests = set([item["name"] for item in iphone_se_junit if item.get("failure") is not None])

        self.assertEqual(successful_tests, {"testSlowTest", "testAlwaysSuccess", "testQuickTest", "testWritingToTestWorkingDir"})
        self.assertEqual(failed_tests, {"testAlwaysFails"})

    def test_plugin_output(self):
        output_path = open("auxiliary/tempfolder/test-results/test_plugin_output.json", 'r')
        json_contents = json.load(output_path)
        
        testing_result_events = []
        tear_down_events = []
        unknown_events = []
        
        for event in json_contents:
            if event["eventType"] == "didObtainTestingResult":
                testing_result_events.append(event)
            elif event["eventType"] == "tearDown":
                tear_down_events.append(event)
            else:
                unknown_events.append(event)
        
        self.check_test_result_events(testing_result_events)
        self.check_tear_down_events(tear_down_events)
        self.check_unknown_events(unknown_events)

    def check_test_result_events(self, events):
        all_test_entries = [testEntry for event in events for testEntry in event["testingResult"]["bucket"]["testEntries"]]
        actual_tests = sorted([entry["methodName"] for entry in all_test_entries])
        expected_tests = sorted(["testAlwaysSuccess", "testWritingToTestWorkingDir", "testSlowTest", "testAlwaysFails", "testQuickTest"])
        self.assertEquals(actual_tests, expected_tests)
        
        all_test_runs = [unfiltered_test_runs for event in events for unfiltered_test_runs in event["testingResult"]["unfilteredTestRuns"]]
        green_tests = [test_run["testEntry"]["methodName"] for test_run in all_test_runs if test_run["succeeded"] == True]
        failed_tests = [test_run["testEntry"]["methodName"] for test_run in all_test_runs if test_run["succeeded"] == False]
        self.assertEquals(sorted(green_tests), sorted(["testAlwaysSuccess", "testWritingToTestWorkingDir", "testSlowTest", "testQuickTest"]))
        self.assertEquals(sorted(failed_tests), sorted(["testAlwaysFails", "testAlwaysFails"]))
    
    def check_tear_down_events(self, events):
        self.assertEqual(len(events), 1)
        
    def check_unknown_events(self, events):
        self.assertEqual(len(events), 0)