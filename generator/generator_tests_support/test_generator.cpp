#include "test_generator.hpp"

#include "generator/borders.hpp"
#include "generator/feature_sorter.hpp"
#include "generator/osm_source.hpp"
#include "generator/raw_generator.hpp"
#include "generator/search_index_builder.hpp"

#include "indexer/classificator_loader.hpp"
#include "indexer/features_offsets_table.hpp"
#include "indexer/index_builder.hpp"
#include "indexer/map_style_reader.hpp"

#include "platform/platform.hpp"

namespace generator
{
namespace tests_support
{

bool MakeFakeBordersFile(std::string const & intemediatePath, std::string const & filename)
{
  auto const borderPath = base::JoinPath(intemediatePath, BORDERS_DIR);
  auto & platform = GetPlatform();
  auto const code = platform.MkDir(borderPath);
  if (code != Platform::EError::ERR_OK && code != Platform::EError::ERR_FILE_ALREADY_EXISTS)
    return false;

  std::vector<m2::PointD> points = {
    {-180.0, -90.0}, {180.0, -90.0}, {180.0, 90.0}, {-180.0, 90.0}, {-180.0, -90.0}
  };
  borders::DumpBorderToPolyFile(borderPath, filename, {m2::RegionD{std::move(points)}});
  return true;
}

TestRawGenerator::TestRawGenerator()
{
  GetStyleReader().SetCurrentStyle(MapStyleMerged);
  classificator::Load();

  SetupTmpFolder("./raw_generator");
}

TestRawGenerator::~TestRawGenerator()
{
  UNUSED_VALUE(Platform::RmDirRecursively(GetTmpPath()));
}

void TestRawGenerator::SetupTmpFolder(std::string const & tmpPath)
{
  m_genInfo.m_cacheDir = m_genInfo.m_intermediateDir = tmpPath;
  UNUSED_VALUE(Platform::RmDirRecursively(tmpPath));
  CHECK(Platform::MkDirChecked(tmpPath), ());
}

void TestRawGenerator::BuildFB(std::string const & osmFilePath, std::string const & mwmName)
{
  m_genInfo.m_nodeStorageType = feature::GenerateInfo::NodeStorageType::Index;
  m_genInfo.m_osmFileName = osmFilePath;
  m_genInfo.m_osmFileType = feature::GenerateInfo::OsmSourceType::XML;

  CHECK(GenerateIntermediateData(m_genInfo), ());

  //CHECK(MakeFakeBordersFile(GetTmpPath(), mwmName), ());

  m_genInfo.m_tmpDir = m_genInfo.m_targetDir = GetTmpPath();
  m_genInfo.m_fileName = mwmName;

  m_genInfo.m_citiesBoundariesFilename = GetCitiesBoundariesPath();

  RawGenerator rawGenerator(m_genInfo);
  rawGenerator.ForceReloadCache();

  rawGenerator.GenerateWorld(false /* cutBordersByWater */);
  rawGenerator.GenerateCountries(true /* isTests */);

  CHECK(rawGenerator.Execute(), ("Error generating", mwmName));
}

void TestRawGenerator::BuildFeatures(std::string const & mwmName)
{
  using namespace feature;
  auto const type = IsWorld(mwmName) ? DataHeader::MapType::World : DataHeader::MapType::Country;
  CHECK(GenerateFinalFeatures(m_genInfo, mwmName, type), ());

  std::string const mwmPath = GetMwmPath(mwmName);

  CHECK(BuildOffsetsTable(mwmPath), ());
  CHECK(indexer::BuildIndexFromDataFile(mwmPath, mwmPath), ());
}

void TestRawGenerator::BuildSearch(std::string const & mwmName)
{
  CHECK(indexer::BuildSearchIndexFromDataFile(mwmName, m_genInfo, true /* forceRebuild */, 1 /* threadsCount */), ());

  if (IsWorld(mwmName))
  {
    generator::OsmIdToBoundariesTable table;
    CHECK(generator::DeserializeBoundariesTable(GetCitiesBoundariesPath(), table), ());
    CHECK(generator::BuildCitiesBoundaries(GetMwmPath(mwmName), table), ());
  }
}

std::string TestRawGenerator::GetMwmPath(std::string const & mwmName) const
{
  return m_genInfo.GetTargetFileName(mwmName, DATA_FILE_EXTENSION);
}

std::string TestRawGenerator::GetCitiesBoundariesPath() const
{
  return m_genInfo.GetTmpFileName(CITIES_BOUNDARIES_FILE_TAG, ".bin");
}

bool TestRawGenerator::IsWorld(std::string const & mwmName) const
{
  return (mwmName == WORLD_FILE_NAME);
}

} // namespace tests_support
} // namespace generator
