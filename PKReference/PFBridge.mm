#import "PFBridge.h"

#include <Core/Util/IVToPIDCalculator.hpp>
#include <Core/Util/IVChecker.hpp>
#include <Core/Gen3/Tools/PIDToIVCalculator.hpp>
#include <Core/Gen3/Tools/SeedToTimeCalculator3.hpp>
#include <Core/Gen4/Tools/SeedToTimeCalculator4.hpp>
#include <Core/Gen3/Generators/StaticGenerator3.hpp>
#include <Core/Gen3/Searchers/StaticSearcher3.hpp>
#include <Core/Gen4/Generators/StaticGenerator4.hpp>
#include <Core/Gen4/Searchers/StaticSearcher4.hpp>
#include <Core/Gen3/Profile3.hpp>
#include <Core/Gen4/Profile4.hpp>
#include <Core/Gen3/StaticTemplate3.hpp>
#include <Core/Gen4/StaticTemplate4.hpp>
#include <Core/Gen3/Encounters3.hpp>
#include <Core/Gen4/Encounters4.hpp>
#include <Core/Parents/Filters/StateFilter.hpp>
#include <Core/Parents/States/State.hpp>
#include <Core/Parents/States/IVToPIDState.hpp>
#include <Core/Gen3/States/PIDToIVState.hpp>
#include <Core/Gen4/States/State4.hpp>
#include <Core/Gen4/SeedTime4.hpp>
#include <Core/Util/DateTime.hpp>
#include <Core/Enum/Method.hpp>
#include <Core/Enum/Lead.hpp>
#include <Core/Enum/Game.hpp>
#include <Core/Enum/Shiny.hpp>

#include <Core/Util/Translator.hpp>
#include <Core/Util/Utilities.hpp>
#include <Core/Gen3/Generators/WildGenerator3.hpp>
#include <Core/Gen3/Searchers/WildSearcher3.hpp>
#include <Core/Gen3/EncounterArea3.hpp>
#include <Core/Gen4/Generators/WildGenerator4.hpp>
#include <Core/Gen4/Searchers/WildSearcher4.hpp>
#include <Core/Gen4/EncounterArea4.hpp>
#include <Core/Gen4/States/WildState4.hpp>
#include <Core/Parents/States/WildState.hpp>
#include <Core/Enum/Encounter.hpp>

#include <Core/Gen3/Generators/EggGenerator3.hpp>
#include <Core/Gen4/Generators/EggGenerator4.hpp>
#include <Core/Gen3/Generators/IDGenerator3.hpp>
#include <Core/Gen4/Generators/IDGenerator4.hpp>
#include <Core/Gen4/Searchers/IDSearcher4.hpp>
#include <Core/Parents/Daycare.hpp>
#include <Core/Parents/States/EggState.hpp>
#include <Core/Gen3/States/EggState3.hpp>
#include <Core/Gen4/States/EggState4.hpp>
#include <Core/Parents/States/IDState.hpp>
#include <Core/Gen4/States/IDState4.hpp>
#include <Core/Parents/Filters/IDFilter.hpp>

#include <Core/Gen3/Generators/GameCubeGenerator.hpp>
#include <Core/Gen3/Generators/PokeSpotGenerator.hpp>
#include <Core/Gen3/Searchers/GameCubeSearcher.hpp>
#include <Core/Gen3/Searchers/ColoSeedSearcher.hpp>
#include <Core/Gen3/Searchers/GalesSeedSearcher.hpp>
#include <Core/Gen3/Searchers/ChannelSeedSearcher.hpp>
#include <Core/Gen3/States/PokeSpotState.hpp>
#include <Core/Gen3/Tools/JirachiPattern.hpp>
#include <Core/Gen3/ShadowTemplate.hpp>
#include <Core/Enum/ShadowType.hpp>
#include <Core/Parents/EncounterArea.hpp>

#include <Core/Gen5/Profile5.hpp>
#include <Core/Gen5/StaticTemplate5.hpp>
#include <Core/Gen5/EncounterArea5.hpp>
#include <Core/Gen5/Encounters5.hpp>
#include <Core/Gen5/Generators/StaticGenerator5.hpp>
#include <Core/Gen5/Generators/WildGenerator5.hpp>
#include <Core/Gen5/States/State5.hpp>
#include <Core/Gen5/States/WildState5.hpp>
#include <Core/Gen5/States/EggState5.hpp>
#include <Core/Gen5/Generators/EggGenerator5.hpp>
#include <Core/Gen5/Generators/IDGenerator5.hpp>
#include <Core/Gen5/Searchers/IVSearcher5.hpp>
#include <Core/Gen5/States/SearcherState5.hpp>
#include <Core/Enum/Buttons.hpp>
#include <Core/Enum/DSType.hpp>
#include <Core/Enum/Language.hpp>

#include <Core/Gen8/Profile8.hpp>
#include <Core/Gen8/StaticTemplate8.hpp>
#include <Core/Gen8/EncounterArea8.hpp>
#include <Core/Gen8/UndergroundArea.hpp>
#include <Core/Gen8/Encounters8.hpp>
#include <Core/Gen8/Den.hpp>
#include <Core/Gen8/Raid.hpp>
#include <Core/Gen8/WB8.hpp>
#include <Core/Gen8/Generators/StaticGenerator8.hpp>
#include <Core/Gen8/Generators/WildGenerator8.hpp>
#include <Core/Gen8/Generators/EggGenerator8.hpp>
#include <Core/Gen8/Generators/IDGenerator8.hpp>
#include <Core/Gen8/Generators/RaidGenerator.hpp>
#include <Core/Gen8/Generators/UndergroundGenerator.hpp>
#include <Core/Gen8/States/State8.hpp>
#include <Core/Gen8/States/WildState8.hpp>
#include <Core/Gen8/States/EggState8.hpp>
#include <Core/Gen8/States/IDState8.hpp>
#include <Core/Gen8/States/UndergroundState.hpp>
#include <Core/Gen8/Filters/UndergroundFilter.hpp>

#include <algorithm>
#include <vector>
#include <cstring>
#include <thread>
#include <atomic>
#include <variant>

// MARK: - Async Search Handle

struct PFAsyncSearch {
    std::variant<WildSearcher3 *, WildSearcher4 *> searcher;
    std::thread thread;
    bool isGen4;

    ~PFAsyncSearch() {
        if (thread.joinable()) thread.join();
        if (isGen4) delete std::get<WildSearcher4 *>(searcher);
        else delete std::get<WildSearcher3 *>(searcher);
    }
};

// MARK: - Helpers

// All-false means "no filter" in Swift convention; normalize to all-true
// so PokeFinder's per-element checks (!natures[i]) don't reject everything.
template <size_t N>
static std::array<bool, N> allowedOrAll(const bool *values)
{
    std::array<bool, N> arr;
    std::copy(values, values + N, arr.begin());
    if (std::none_of(arr.begin(), arr.end(), [](bool b) { return b; })) arr.fill(true);
    return arr;
}

// PokéFinder's filters have a `skip` that passes everything, IVs, natures
// and Hidden Powers included, so it's only for when nothing is filtered.
template <size_t N>
static bool allTrue(const std::array<bool, N> &arr)
{
    return std::all_of(arr.begin(), arr.end(), [](bool b) { return b; });
}

static bool filtersNothing(uint8_t gender, uint8_t ability, uint8_t shiny,
                           const std::array<u8, 6> &min, const std::array<u8, 6> &max,
                           const std::array<bool, 25> &natures, const std::array<bool, 16> &powers)
{
    for (int i = 0; i < 6; i++) {
        if (min[i] > 0 || max[i] < 31) return false;
    }
    return gender == 255 && ability == 255 && shiny == 255 && allTrue(natures) && allTrue(powers);
}

static StateFilter makeFilter(uint8_t gender, uint8_t ability, uint8_t shiny,
                               const uint8_t ivMin[6], const uint8_t ivMax[6],
                               const bool natures[25], const bool powers[16])
{
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto natArr = allowedOrAll<25>(natures);
    auto powArr = allowedOrAll<16>(powers);

    bool skip = filtersNothing(gender, ability, shiny, min, max, natArr, powArr);
    return StateFilter(gender, ability, shiny, 0, 255, 0, 255, skip, min, max, natArr, powArr);
}

static PFGeneratorState convertGenState(const GeneratorState &s)
{
    PFGeneratorState r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFGeneratorState4 convertGenState4(const GeneratorState4 &s)
{
    PFGeneratorState4 r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.call = s.getCall();
    r.chatot = s.getChatot();
    return r;
}

static PFSearcherState convertSearchState(const SearcherState &s)
{
    PFSearcherState r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFSearcherState4 convertSearchState4(const SearcherState4 &s)
{
    PFSearcherState4 r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    return r;
}

static PFDateTime convertDateTime(const DateTime &dt)
{
    PFDateTime r;
    auto date = dt.getDate();
    auto time = dt.getTime();
    auto parts = date.getParts();
    r.year = parts.year;
    r.month = parts.month;
    r.day = parts.day;
    r.hour = time.hour();
    r.minute = time.minute();
    r.second = time.second();
    return r;
}

static WildStateFilter makeWildFilter(uint8_t gender, uint8_t ability, uint8_t shiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       const bool encounterSlots[12])
{
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto natArr = allowedOrAll<25>(natures);
    auto powArr = allowedOrAll<16>(powers);

    std::array<bool, 12> slotArr;
    std::copy(encounterSlots, encounterSlots + 12, slotArr.begin());

    bool skip = filtersNothing(gender, ability, shiny, min, max, natArr, powArr) && allTrue(slotArr);
    return WildStateFilter(gender, ability, shiny, 0, 255, 0, 255, skip, min, max, natArr, powArr, slotArr);
}

static PFWildGeneratorState convertWildGenState(const WildGeneratorState &s)
{
    PFWildGeneratorState r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

static PFWildSearcherState convertWildSearchState(const WildSearcherState &s)
{
    PFWildSearcherState r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

static PFEncounterArea convertEncounterArea(const EncounterArea &area)
{
    PFEncounterArea r;
    r.location = area.getLocation();
    r.rate = area.getRate();
    r.encounter = static_cast<uint8_t>(area.getEncounter());
    r.slotCount = area.getCount();
    auto &pokemon = area.getPokemon();
    for (int i = 0; i < 12; i++) {
        r.slots[i].specie = pokemon[i].getSpecie();
        r.slots[i].form = pokemon[i].getForm();
        r.slots[i].minLevel = pokemon[i].getMinLevel();
        r.slots[i].maxLevel = pokemon[i].getMaxLevel();
    }
    return r;
}

static EncounterArea3 findEncounterArea3(Encounter encounter, const EncounterSettings3 &settings,
                                          Game version, uint8_t location)
{
    auto areas = Encounters3::getEncounters(encounter, settings, version);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea3(0, 0, Encounter::Grass, {});
}

static EncounterArea4 findEncounterArea4(Encounter encounter, const EncounterSettings4 &settings,
                                          const Profile4 &profile, uint8_t location)
{
    auto areas = Encounters4::getEncounters(encounter, settings, &profile);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea4(0, 0, Encounter::Grass, {});
}

static PFWildGeneratorState4 convertWildGenState4(const WildGeneratorState4 &s)
{
    PFWildGeneratorState4 r;
    r.seed = 0;
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    r.call = s.getCall();
    r.chatot = s.getChatot();
    return r;
}

static PFWildSearcherState4 convertWildSearchState4(const WildSearcherState4 &s)
{
    PFWildSearcherState4 r;
    r.seed = s.getSeed();
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

// MARK: - Memory Management

extern "C" void pf_freeResults(void *ptr)
{
    free(ptr);
}

extern "C" void pf_freeString(char *str)
{
    free(str);
}

extern "C" void pf_freeStringArray(char **arr, int count)
{
    for (int i = 0; i < count; i++) free(arr[i]);
    free(arr);
}

// MARK: - IV To PID

extern "C" PFIVToPIDResult *pf_ivToPID(uint8_t hp, uint8_t atk, uint8_t def,
                                         uint8_t spa, uint8_t spd, uint8_t spe,
                                         uint8_t nature, uint16_t tid,
                                         int *outCount)
{
    auto results = IVToPIDCalculator::calculatePIDs(hp, atk, def, spa, spd, spe, nature, tid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIVToPIDResult *>(malloc(sizeof(PFIVToPIDResult) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        out[i].pid = results[i].getPID();
        out[i].sid = results[i].getSID();
        out[i].method = static_cast<uint8_t>(results[i].getMethod());
    }
    return out;
}

// MARK: - PID To IV

extern "C" PFPIDToIVResult *pf_pidToIV(uint32_t pid, int *outCount)
{
    auto results = PIDToIVCalculator::calculateIVs(pid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFPIDToIVResult *>(malloc(sizeof(PFPIDToIVResult) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        auto ivs = results[i].getIVs();
        for (int j = 0; j < 6; j++) out[i].ivs[j] = ivs[j];
        out[i].method = static_cast<uint8_t>(results[i].getMethod());
    }
    return out;
}

// MARK: - Seed To Time Gen 3

extern "C" PFOriginSeed3 pf_seedToTimeOriginSeed3(uint32_t seed)
{
    u32 advances = 0;
    u16 origin = SeedToTimeCalculator3::calculateOriginSeed(seed, advances);
    return { origin, advances };
}

extern "C" PFDateTime *pf_seedToTime3(uint32_t seed, uint16_t year, int *outCount)
{
    auto results = SeedToTimeCalculator3::calculateTimes(seed, year);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFDateTime *>(malloc(sizeof(PFDateTime) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertDateTime(results[i]);
    }
    return out;
}

// MARK: - Seed To Time Gen 4

extern "C" PFSeedTime4 *pf_seedToTime4(uint32_t seed, uint16_t year,
                                          bool forceSecond, uint8_t forcedSecond,
                                          int *outCount)
{
    auto results = SeedToTimeCalculator4::calculateTimes(seed, year, forceSecond, forcedSecond);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSeedTime4 *>(malloc(sizeof(PFSeedTime4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].dateTime = convertDateTime(results[i].getDateTime());
        out[i].delay = results[i].getDelay();
    }
    return out;
}

// MARK: - Gen 3 Static Generator

extern "C" PFGeneratorState *pf_staticGenerate3(uint32_t seed,
                                                  uint32_t initialAdvances,
                                                  uint32_t maxAdvances,
                                                  uint32_t offset,
                                                  uint8_t method,
                                                  uint16_t tid, uint16_t sid,
                                                  uint8_t game,
                                                  bool deadBattery,
                                                  uint8_t gender, uint8_t ability, uint8_t shiny,
                                                  const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                  const bool natures[25], const bool powers[16],
                                                  int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    StaticTemplate3 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, false);

    StaticGenerator3 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), tmpl, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - Gen 3 Static Template Generator and IV Calculator

// Ten Lines' check_seeds_static generator (calibration.cpp): a static
// encounter's own template, so gender comes from its species.
extern "C" PFGeneratorState *pf_staticTemplateGenerate3(uint32_t seed,
                                                          uint32_t initialAdvances,
                                                          uint32_t maxAdvances,
                                                          uint32_t offset,
                                                          uint8_t method,
                                                          int staticType, int staticIndex,
                                                          uint16_t tid, uint16_t sid,
                                                          uint32_t game,
                                                          uint8_t gender, uint8_t ability, uint8_t shiny,
                                                          const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                          const bool natures[25], const bool powers[16],
                                                          int *outCount)
{
    *outCount = 0;
    int size = 0;
    const StaticTemplate3 *templates = Encounters3::getStaticEncounters(staticType, &size);
    if (!templates || staticIndex < 0 || staticIndex >= size) return nullptr;

    Profile3 profile("", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    StaticGenerator3 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), templates[staticIndex], profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// Ten Lines' calc_ivs_static (iv_calc.cpp): the IVs a static encounter's
// stats allow, from its template's base stats, per stat as min and max.
// A stat no IV fits gives min 32, max 0.
extern "C" bool pf_calcIVsStatic3(int staticType, int staticIndex,
                                   const uint8_t *levels, const uint16_t *stats, int count,
                                   uint8_t nature, uint8_t outMin[6], uint8_t outMax[6])
{
    int size = 0;
    const StaticTemplate3 *templates = Encounters3::getStaticEncounters(staticType, &size);
    if (!templates || staticIndex < 0 || staticIndex >= size || count <= 0) return false;

    const std::array<u8, 6> baseStats = templates[staticIndex].getInfo()->getStats();
    std::vector<u8> parsedLevels;
    std::vector<std::array<u16, 6>> parsedStats;
    for (int i = 0; i < count; i++) {
        parsedLevels.push_back(levels[i]);
        parsedStats.push_back({ stats[i * 6], stats[i * 6 + 1], stats[i * 6 + 2],
                                stats[i * 6 + 3], stats[i * 6 + 4], stats[i * 6 + 5] });
    }

    auto possible = IVChecker::calculateIVRange(baseStats, parsedStats, parsedLevels, nature, 255, 255);
    for (int i = 0; i < 6; i++) {
        auto minElement = std::min_element(possible[i].begin(), possible[i].end());
        auto maxElement = std::max_element(possible[i].begin(), possible[i].end());
        if (minElement == possible[i].end() || maxElement == possible[i].end()) {
            outMin[i] = 32;
            outMax[i] = 0;
        } else {
            outMin[i] = *minElement;
            outMax[i] = *maxElement;
        }
    }
    return true;
}

// MARK: - Gen 3 Static Searcher

extern "C" PFSearcherState *pf_staticSearch3(uint8_t method,
                                               uint16_t tid, uint16_t sid,
                                               uint8_t game,
                                               bool deadBattery,
                                               uint8_t gender, uint8_t ability, uint8_t shiny,
                                               const uint8_t ivMin[6], const uint8_t ivMax[6],
                                               const bool natures[25], const bool powers[16],
                                               int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    StaticTemplate3 tmpl(static_cast<Game>(game), 0, 0, Shiny::Random, 1, false);

    StaticSearcher3 searcher(static_cast<Method>(method), profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max, &tmpl);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState *>(malloc(sizeof(PFSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState(results[i]);
    }
    return out;
}

// MARK: - Gen 3 Static Searcher (Async)

// PokéFinder's searcher on its own thread, so results and progress can be
// read as it goes. With a static encounter's template (staticType 0–7),
// gender and bugged roamers' IVs follow it; without one (-1), a stand-in
// like pf_staticSearch3's, whose results are genderless.
struct PFStaticSearch3 {
    StaticTemplate3 tmpl;
    StaticSearcher3 searcher;
    std::thread thread;
    std::atomic<bool> done { false };

    PFStaticSearch3(const StaticTemplate3 &tmpl, Method method, const Profile3 &profile, const StateFilter &filter) :
        tmpl(tmpl), searcher(method, profile, filter)
    {
    }

    ~PFStaticSearch3()
    {
        if (thread.joinable()) thread.join();
    }
};

extern "C" PFStaticSearch3Handle pf_staticSearch3_start(uint8_t method,
                                                         uint16_t tid, uint16_t sid,
                                                         uint32_t game,
                                                         int staticType, int staticIndex,
                                                         uint8_t gender, uint8_t ability, uint8_t shiny,
                                                         const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                         const bool natures[25], const bool powers[16])
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(gender, ability, shiny, ivMin, ivMax, natures, powers);

    // The stand-in has no game, as pf_staticSearch3's from the Finder had:
    // species 0 is then genderless, where a Gen 3 game's would say male.
    StaticTemplate3 tmpl(Game::None, 0, 0, Shiny::Random, 1, false);
    int size = 0;
    const StaticTemplate3 *templates = staticType >= 0 ? Encounters3::getStaticEncounters(staticType, &size) : nullptr;
    if (templates && staticIndex >= 0 && staticIndex < size) tmpl = templates[staticIndex];

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    // The searcher counts each IV combination it tries; it has no total of
    // its own, so progress reads as a percentage.
    u64 total = 1;
    for (int i = 0; i < 6; i++) total *= min[i] <= max[i] ? static_cast<u64>(max[i] - min[i] + 1) : 0;

    auto *handle = new PFStaticSearch3(tmpl, static_cast<Method>(method), profile, filter);
    handle->searcher.setMaxProgress(total > 0 ? total : 1);
    handle->thread = std::thread([handle, min, max]() {
        handle->searcher.startSearch(min, max, &handle->tmpl);
        handle->done = true;
    });
    return handle;
}

extern "C" int pf_staticSearch3_progress(PFStaticSearch3Handle h)
{
    return static_cast<PFStaticSearch3 *>(h)->searcher.getProgress();
}

extern "C" bool pf_staticSearch3_done(PFStaticSearch3Handle h)
{
    return static_cast<PFStaticSearch3 *>(h)->done;
}

// The results found since the last call.
extern "C" PFSearcherState *pf_staticSearch3_getResults(PFStaticSearch3Handle h, int *outCount)
{
    auto results = static_cast<PFStaticSearch3 *>(h)->searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState *>(malloc(sizeof(PFSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState(results[i]);
    }
    return out;
}

extern "C" void pf_staticSearch3_cancel(PFStaticSearch3Handle h)
{
    static_cast<PFStaticSearch3 *>(h)->searcher.cancelSearch();
}

// Waits for the search's thread, so cancel first to stop early.
extern "C" void pf_staticSearch3_free(PFStaticSearch3Handle h)
{
    delete static_cast<PFStaticSearch3 *>(h);
}

// MARK: - Gen 4 Static Generator

// A Gen 4 static encounter's template (staticType 0–7), or, without one
// (-1), a stand-in with no game, whose results are genderless.
static StaticTemplate4 staticTemplate4(int staticType, int staticIndex, Method method)
{
    int size = 0;
    const StaticTemplate4 *templates = staticType >= 0 ? Encounters4::getStaticEncounters(staticType, &size) : nullptr;
    if (templates && staticIndex >= 0 && staticIndex < size) return templates[staticIndex];
    return StaticTemplate4(Game::None, 0, 0, Shiny::Random, 1, method);
}

extern "C" PFGeneratorState4 *pf_staticGenerate4(uint32_t seed,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint8_t method,
                                                    uint8_t lead,
                                                    int staticType, int staticIndex,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    StaticTemplate4 tmpl = staticTemplate4(staticType, staticIndex, static_cast<Method>(method));

    StaticGenerator4 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), static_cast<Lead>(lead),
                                tmpl, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState4 *>(malloc(sizeof(PFGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState4(results[i]);
    }
    return out;
}

// MARK: - Gen 4 Static Searcher (Async)

// PokéFinder's searcher on its own thread, as pf_staticSearch3_start's: read
// results and progress as it goes, until done.
struct PFStaticSearch4 {
    StaticTemplate4 tmpl;
    StaticSearcher4 searcher;
    std::thread thread;
    std::atomic<bool> done { false };

    PFStaticSearch4(const StaticTemplate4 &tmpl, u32 minAdvance, u32 maxAdvance, u32 minDelay, u32 maxDelay,
                    Method method, Lead lead, const Profile4 &profile, const StateFilter &filter) :
        tmpl(tmpl), searcher(minAdvance, maxAdvance, minDelay, maxDelay, method, lead, profile, filter)
    {
    }

    ~PFStaticSearch4()
    {
        if (thread.joinable()) thread.join();
    }
};

extern "C" PFStaticSearch4Handle pf_staticSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                                         uint32_t minDelay, uint32_t maxDelay,
                                                         uint8_t method, uint8_t lead,
                                                         int staticType, int staticIndex,
                                                         uint16_t tid, uint16_t sid, uint32_t game,
                                                         uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                         const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                         const bool natures[25], const bool powers[16])
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);
    StaticTemplate4 tmpl = staticTemplate4(staticType, staticIndex, static_cast<Method>(method));

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    // Each IV combination it tries, as pf_staticSearch3_start counts.
    u64 total = 1;
    for (int i = 0; i < 6; i++) total *= min[i] <= max[i] ? static_cast<u64>(max[i] - min[i] + 1) : 0;

    auto *handle = new PFStaticSearch4(tmpl, minAdvance, maxAdvance, minDelay, maxDelay,
                                       static_cast<Method>(method), static_cast<Lead>(lead), profile, filter);
    handle->searcher.setMaxProgress(total > 0 ? total : 1);
    handle->thread = std::thread([handle, min, max]() {
        handle->searcher.startSearch(min, max, &handle->tmpl);
        handle->done = true;
    });
    return handle;
}

extern "C" int pf_staticSearch4_progress(PFStaticSearch4Handle h)
{
    return static_cast<PFStaticSearch4 *>(h)->searcher.getProgress();
}

extern "C" bool pf_staticSearch4_done(PFStaticSearch4Handle h)
{
    return static_cast<PFStaticSearch4 *>(h)->done;
}

// The results found since the last call.
extern "C" PFSearcherState4 *pf_staticSearch4_getResults(PFStaticSearch4Handle h, int *outCount)
{
    auto results = static_cast<PFStaticSearch4 *>(h)->searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState4 *>(malloc(sizeof(PFSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState4(results[i]);
    }
    return out;
}

extern "C" void pf_staticSearch4_cancel(PFStaticSearch4Handle h)
{
    static_cast<PFStaticSearch4 *>(h)->searcher.cancelSearch();
}

// Waits for the search's thread, so cancel first to stop early.
extern "C" void pf_staticSearch4_free(PFStaticSearch4Handle h)
{
    delete static_cast<PFStaticSearch4 *>(h);
}

// MARK: - Translator

extern "C" void pf_initTranslator(const char *locale)
{
    Translator::init(std::string(locale));
}

static char *copyString(const std::string &s)
{
    char *out = static_cast<char *>(malloc(s.size() + 1));
    std::memcpy(out, s.c_str(), s.size() + 1);
    return out;
}

extern "C" char *pf_getSpecieName(uint16_t specie)
{
    return copyString(Translator::getSpecie(specie));
}

extern "C" char *pf_getFormName(uint16_t specie, uint8_t form)
{
    return copyString(Translator::getForm(specie, form));
}

extern "C" char *pf_getAbilityName(uint16_t ability)
{
    return copyString(Translator::getAbility(ability));
}

extern "C" char *pf_getNatureName(uint8_t nature)
{
    return copyString(Translator::getNature(nature));
}

extern "C" char *pf_getHiddenPowerName(uint8_t power)
{
    return copyString(Translator::getHiddenPower(power));
}

extern "C" char *pf_getItemName(uint16_t item)
{
    return copyString(Translator::getItem(item));
}

extern "C" char *pf_getMoveName(uint16_t move)
{
    return copyString(Translator::getMove(move));
}

extern "C" char **pf_getNatureNames(int *outCount)
{
    auto &natures = Translator::getNatures();
    *outCount = static_cast<int>(natures.size());
    auto **out = static_cast<char **>(malloc(sizeof(char *) * natures.size()));
    for (size_t i = 0; i < natures.size(); i++) {
        out[i] = copyString(natures[i]);
    }
    return out;
}

extern "C" char **pf_getHiddenPowerNames(int *outCount)
{
    auto &powers = Translator::getHiddenPowers();
    *outCount = static_cast<int>(powers.size());
    auto **out = static_cast<char **>(malloc(sizeof(char *) * powers.size()));
    for (size_t i = 0; i < powers.size(); i++) {
        out[i] = copyString(powers[i]);
    }
    return out;
}

extern "C" char **pf_getLocationNames(const uint16_t *locationNums, int count, uint32_t game)
{
    std::vector<u16> nums(locationNums, locationNums + count);
    auto names = Translator::getLocations(nums, static_cast<Game>(game));
    auto **out = static_cast<char **>(malloc(sizeof(char *) * names.size()));
    for (size_t i = 0; i < names.size(); i++) {
        out[i] = copyString(names[i]);
    }
    return out;
}

// MARK: - Encounter Data

extern "C" PFEncounterArea *pf_getEncounters3(uint8_t encounter, uint32_t game,
                                                bool feebasTile, int *outCount)
{
    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    auto areas = Encounters3::getEncounters(static_cast<Encounter>(encounter),
                                             settings, static_cast<Game>(game));
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFEncounterArea *pf_getEncounters4(uint8_t encounter, uint32_t game,
                                                uint16_t tid, uint16_t sid,
                                                int time, bool swarm,
                                                uint32_t dual,
                                                uint16_t replacement0, uint16_t replacement1,
                                                bool feebasTile, bool radar,
                                                int radio,
                                                const uint8_t blocks[5],
                                                int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    EncounterSettings4 settings;
    settings.time = time;
    settings.swarm = swarm;

    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = static_cast<Game>(dual);
        settings.dppt.replacement = { replacement0, replacement1 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = radar;
    } else {
        settings.hgss.radio = radio;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = blocks[i];
    }

    auto areas = Encounters4::getEncounters(static_cast<Encounter>(encounter),
                                             settings, &profile);
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters3(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate3 *templates = Encounters3::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
        out[i].method = 0;
        out[i].ivCount = templates[i].getIVCount();
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters4(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate4 *templates = Encounters4::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
        out[i].method = static_cast<uint8_t>(templates[i].getMethod());
        out[i].ivCount = templates[i].getIVCount();
    }
    return out;
}

// MARK: - Wild Generator Gen 3

extern "C" PFWildGeneratorState *pf_wildGenerate3(uint32_t seed,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint8_t method,
                                                    uint8_t lead,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    bool deadBattery,
                                                    bool feebasTile,
                                                    uint8_t encounter,
                                                    uint8_t location,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    const bool encounterSlots[12],
                                                    int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    WildGenerator3 generator(initialAdvances, maxAdvances, offset,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              feebasTile, area, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState *>(malloc(sizeof(PFWildGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState(results[i]);
    }
    return out;
}

// MARK: - Wild Searcher Gen 3

extern "C" PFWildSearcherState *pf_wildSearch3(uint8_t method,
                                                 uint8_t lead,
                                                 uint16_t tid, uint16_t sid,
                                                 uint32_t game,
                                                 bool deadBattery,
                                                 bool feebasTile,
                                                 uint8_t encounter,
                                                 uint8_t location,
                                                 uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                 const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                 const bool natures[25], const bool powers[16],
                                                 const bool encounterSlots[12],
                                                 int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    WildSearcher3 searcher(static_cast<Method>(method), static_cast<Lead>(lead),
                            feebasTile, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState *>(malloc(sizeof(PFWildSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState(results[i]);
    }
    return out;
}

// MARK: - Wild Generator Gen 4

extern "C" PFWildGeneratorState4 *pf_wildGenerate4(uint32_t seed,
                                                     uint32_t initialAdvances,
                                                     uint32_t maxAdvances,
                                                     uint32_t offset,
                                                     uint8_t method,
                                                     uint8_t lead,
                                                     uint16_t tid, uint16_t sid,
                                                     uint32_t game,
                                                     bool feebasTile,
                                                     uint8_t encounter,
                                                     uint8_t location,
                                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                     const bool natures[25], const bool powers[16],
                                                     const bool encounterSlots[12],
                                                     int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    WildGenerator4 generator(initialAdvances, maxAdvances, offset,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              feebasTile, false, false, 0, area, profile, filter);

    auto results = generator.generate(seed, 0);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState4 *>(malloc(sizeof(PFWildGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState4(results[i]);
    }
    return out;
}

// MARK: - Wild Searcher Gen 4

extern "C" PFWildSearcherState4 *pf_wildSearch4(uint32_t minAdvance, uint32_t maxAdvance,
                                                  uint32_t minDelay, uint32_t maxDelay,
                                                  uint8_t method,
                                                  uint8_t lead,
                                                  uint16_t tid, uint16_t sid,
                                                  uint32_t game,
                                                  bool feebasTile,
                                                  uint8_t encounter,
                                                  uint8_t location,
                                                  uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                  const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                  const bool natures[25], const bool powers[16],
                                                  const bool encounterSlots[12],
                                                  int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    WildSearcher4 searcher(minAdvance, maxAdvance, minDelay, maxDelay,
                            static_cast<Method>(method), static_cast<Lead>(lead),
                            feebasTile, false, false, 0, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    searcher.startSearch(min, max, 0);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState4 *>(malloc(sizeof(PFWildSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState4(results[i]);
    }
    return out;
}

// MARK: - Async Wild Searcher Gen 3

extern "C" PFSearchHandle pf_wildSearch3_start(uint8_t method, uint8_t lead,
                                                uint16_t tid, uint16_t sid,
                                                uint32_t game, bool deadBattery, bool feebasTile,
                                                uint8_t encounter, uint8_t location,
                                                uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                const bool natures[25], const bool powers[16],
                                                const bool encounterSlots[12])
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings3 settings;
    settings.feebasTile = feebasTile;
    EncounterArea3 area = findEncounterArea3(static_cast<Encounter>(encounter), settings,
                                              static_cast<Game>(game), location);

    auto *searcher = new WildSearcher3(static_cast<Method>(method), static_cast<Lead>(lead),
                                        feebasTile, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto *handle = new PFAsyncSearch();
    handle->searcher = searcher;
    handle->isGen4 = false;
    handle->thread = std::thread([searcher, min, max]() {
        searcher->startSearch(min, max);
    });

    return static_cast<PFSearchHandle>(handle);
}

// MARK: - Async Wild Searcher Gen 4

extern "C" PFSearchHandle pf_wildSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                                uint32_t minDelay, uint32_t maxDelay,
                                                uint8_t method, uint8_t lead,
                                                uint16_t tid, uint16_t sid,
                                                uint32_t game, bool feebasTile,
                                                uint8_t encounter, uint8_t location,
                                                uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                const bool natures[25], const bool powers[16],
                                                const bool encounterSlots[12])
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings4 settings;
    settings.time = 0;
    settings.swarm = false;
    if ((static_cast<Game>(game) & Game::DPPt) != Game::None) {
        settings.dppt.dual = Game::None;
        settings.dppt.replacement = { 0, 0 };
        settings.dppt.feebasTile = feebasTile;
        settings.dppt.radar = false;
    } else {
        settings.hgss.radio = 0;
        for (int i = 0; i < 5; i++) settings.hgss.blocks[i] = 0;
    }

    EncounterArea4 area = findEncounterArea4(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    auto *searcher = new WildSearcher4(minAdvance, maxAdvance, minDelay, maxDelay,
                                        static_cast<Method>(method), static_cast<Lead>(lead),
                                        feebasTile, false, false, 0, area, profile, filter);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto *handle = new PFAsyncSearch();
    handle->searcher = searcher;
    handle->isGen4 = true;
    handle->thread = std::thread([searcher, min, max]() {
        searcher->startSearch(min, max, 0);
    });

    return static_cast<PFSearchHandle>(handle);
}

// MARK: - Async Search Polling

extern "C" int pf_search_progress(PFSearchHandle handle)
{
    auto *h = static_cast<PFAsyncSearch *>(handle);
    if (h->isGen4) return std::get<WildSearcher4 *>(h->searcher)->getProgress();
    return std::get<WildSearcher3 *>(h->searcher)->getProgress();
}

extern "C" PFWildSearcherState *pf_search3_getResults(PFSearchHandle handle, int *outCount)
{
    auto *searcher = std::get<WildSearcher3 *>(static_cast<PFAsyncSearch *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState *>(malloc(sizeof(PFWildSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState(results[i]);
    }
    return out;
}

extern "C" PFWildSearcherState4 *pf_search4_getResults(PFSearchHandle handle, int *outCount)
{
    auto *searcher = std::get<WildSearcher4 *>(static_cast<PFAsyncSearch *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearcherState4 *>(malloc(sizeof(PFWildSearcherState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchState4(results[i]);
    }
    return out;
}

extern "C" void pf_search_cancel(PFSearchHandle handle)
{
    auto *h = static_cast<PFAsyncSearch *>(handle);
    if (h->isGen4) std::get<WildSearcher4 *>(h->searcher)->cancelSearch();
    else std::get<WildSearcher3 *>(h->searcher)->cancelSearch();
}

extern "C" void pf_search_free(PFSearchHandle handle)
{
    delete static_cast<PFAsyncSearch *>(handle);
}

// MARK: - Egg Generator Gen 3

extern "C" PFEggGeneratorState3 *pf_eggGenerate3(uint32_t seedHeld, uint32_t seedPickup,
                                                    uint32_t initialAdvances, uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint32_t initialAdvancesPickup, uint32_t maxAdvancesPickup,
                                                    uint32_t offsetPickup,
                                                    uint8_t calibration, uint8_t minRedraw, uint8_t maxRedraw,
                                                    uint8_t method, uint8_t compatibility,
                                                    const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                                    uint8_t parentAAbility, uint8_t parentBAbility,
                                                    uint8_t parentAGender, uint8_t parentBGender,
                                                    uint8_t parentAItem, uint8_t parentBItem,
                                                    uint8_t parentANature, uint8_t parentBNature,
                                                    uint16_t eggSpecie, bool masuda,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game, bool deadBattery,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, deadBattery);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator3 generator(initialAdvances, maxAdvances, offset,
                             initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                             calibration, minRedraw, maxRedraw,
                             static_cast<Method>(method), compatibility, daycare, profile, filter);

    auto results = generator.generate(seedHeld, seedPickup);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState3 *>(malloc(sizeof(PFEggGeneratorState3) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].redraws = s.getRedraws();
        out[i].pickupAdvances = s.getPickupAdvances();
    }
    return out;
}

// MARK: - Egg Generator Gen 4

extern "C" PFEggGeneratorState4 *pf_eggGenerate4(uint32_t seedHeld, uint32_t seedPickup,
                                                    uint32_t initialAdvances, uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint32_t initialAdvancesPickup, uint32_t maxAdvancesPickup,
                                                    uint32_t offsetPickup,
                                                    const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                                    uint8_t parentAAbility, uint8_t parentBAbility,
                                                    uint8_t parentAGender, uint8_t parentBGender,
                                                    uint8_t parentAItem, uint8_t parentBItem,
                                                    uint8_t parentANature, uint8_t parentBNature,
                                                    uint16_t eggSpecie, bool masuda,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile4 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator4 generator(initialAdvances, maxAdvances, offset,
                             initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                             daycare, profile, filter);

    auto results = generator.generate(seedHeld, seedPickup);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState4 *>(malloc(sizeof(PFEggGeneratorState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].pickupAdvances = s.getPickupAdvances();
        out[i].call = s.getCall();
        out[i].chatot = s.getChatot();
    }
    return out;
}

// MARK: - ID Generator Gen 3 (Ruby/Sapphire)

extern "C" PFIDState *pf_idGenerate3_RS(uint16_t seed,
                                          uint32_t initialAdvances, uint32_t maxAdvances,
                                          int *outCount)
{
    IDFilter filter({}, {}, {}, {}, {}, {});
    IDGenerator3 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generateRS(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState *>(malloc(sizeof(PFIDState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - ID Generator Gen 3 (FRLG/Emerald)

extern "C" PFIDState *pf_idGenerate3_FRLGE(uint16_t tid,
                                              uint32_t initialAdvances, uint32_t maxAdvances,
                                              int *outCount)
{
    IDFilter filter({}, {}, {}, {}, {}, {});
    IDGenerator3 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generateFRLGE(tid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState *>(malloc(sizeof(PFIDState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - ID Generator Gen 4

extern "C" PFIDState4 *pf_idGenerate4(uint32_t minDelay, uint32_t maxDelay,
                                        uint16_t year, uint8_t month, uint8_t day,
                                        uint8_t hour, uint8_t minute,
                                        uint16_t targetTID, bool filterTID,
                                        uint16_t targetSID, bool filterSID,
                                        int *outCount)
{
    std::vector<u16> tidFilter;
    std::vector<u16> sidFilter;
    if (filterTID) tidFilter.push_back(targetTID);
    if (filterSID) sidFilter.push_back(targetSID);

    IDFilter filter(tidFilter, sidFilter, {}, {}, {}, {});
    IDGenerator4 generator(minDelay, maxDelay, year, month, day, hour, minute, filter);

    auto results = generator.generate();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState4 *>(malloc(sizeof(PFIDState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        out[i].delay = results[i].getDelay();
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
        out[i].seconds = results[i].getSeconds();
    }
    return out;
}

// MARK: - ID Searcher Gen 4 (Async)

struct PFIDSearch4 {
    IDSearcher4 *searcher;
    std::thread thread;
    std::atomic<bool> done { false };

    ~PFIDSearch4() {
        if (thread.joinable()) thread.join();
        delete searcher;
    }
};

extern "C" PFIDSearch4Handle pf_idSearch4_start(bool infinite, uint16_t year,
                                                  uint32_t minDelay, uint32_t maxDelay,
                                                  uint16_t targetTID, bool filterTID,
                                                  uint16_t targetSID, bool filterSID,
                                                  uint16_t targetTSV, bool filterTSV)
{
    std::vector<u16> tidFilter, sidFilter, tsvFilter;
    if (filterTID) tidFilter.push_back(targetTID);
    if (filterSID) sidFilter.push_back(targetSID);
    if (filterTSV) tsvFilter.push_back(targetTSV);

    IDFilter filter(tidFilter, sidFilter, {}, tsvFilter, {}, {});
    auto *searcher = new IDSearcher4(filter);

    // IDSearcher4 counts each seed it tries but has no total of its own:
    // every delay, with each of the 256 second bytes and 24 hours. Infinite
    // goes to 0xE8FFFF, as startSearch does.
    u32 last = infinite ? 0xe8ffff : maxDelay;
    u64 total = last >= minDelay ? static_cast<u64>(last - minDelay + 1) * 256 * 24 : 1;
    searcher->setMaxProgress(total);

    auto *handle = new PFIDSearch4();
    handle->searcher = searcher;
    handle->thread = std::thread([handle, searcher, infinite, year, minDelay, maxDelay]() {
        searcher->startSearch(infinite, year, minDelay, maxDelay);
        handle->done = true;
    });
    return handle;
}

extern "C" bool pf_idSearch4_done(PFIDSearch4Handle h)
{
    return static_cast<PFIDSearch4 *>(h)->done;
}

extern "C" int pf_idSearch4_progress(PFIDSearch4Handle h)
{
    auto *handle = static_cast<PFIDSearch4 *>(h);
    return handle->searcher->getProgress();
}

extern "C" PFIDState4 *pf_idSearch4_getResults(PFIDSearch4Handle h, int *outCount)
{
    auto *handle = static_cast<PFIDSearch4 *>(h);
    auto results = handle->searcher->getResults();

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState4 *>(malloc(sizeof(PFIDState4) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].seed = results[i].getSeed();
        out[i].delay = results[i].getDelay();
        out[i].advances = 0;
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = (results[i].getTID() ^ results[i].getSID()) >> 3;
        out[i].seconds = 0;
    }
    return out;
}

extern "C" void pf_idSearch4_cancel(PFIDSearch4Handle h)
{
    auto *handle = static_cast<PFIDSearch4 *>(h);
    handle->searcher->cancelSearch();
}

extern "C" void pf_idSearch4_free(PFIDSearch4Handle h)
{
    auto *handle = static_cast<PFIDSearch4 *>(h);
    delete handle;
}

// MARK: - GameCube Shadow Templates

extern "C" PFShadowTemplateInfo *pf_getShadowTemplates(int *outCount)
{
    int size = 0;
    const ShadowTemplate *templates = Encounters3::getShadowTeams(&size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFShadowTemplateInfo *>(malloc(sizeof(PFShadowTemplateInfo) * size));
    for (int i = 0; i < size; i++) {
        out[i].specie = templates[i].getSpecie();
        out[i].level = templates[i].getLevel();
        out[i].shadowType = static_cast<uint8_t>(templates[i].getType());
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
    }
    return out;
}

// MARK: - GameCube Shadow Generator

extern "C" PFGeneratorState *pf_gamecubeGenerateShadow(uint32_t seed,
                                                        uint32_t initialAdvances,
                                                        uint32_t maxAdvances,
                                                        uint32_t offset,
                                                        int shadowIndex,
                                                        bool unset,
                                                        uint16_t tid, uint16_t sid,
                                                        uint32_t game,
                                                        uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                        const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                        const bool natures[25], const bool powers[16],
                                                        int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const ShadowTemplate *tmpl = Encounters3::getShadowTeam(shadowIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeGenerator generator(initialAdvances, maxAdvances, offset, Method::XDColo, unset, profile, filter);
    auto results = generator.generate(seed, tmpl);

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - GameCube Static Generator

extern "C" PFGeneratorState *pf_gamecubeGenerateStatic(uint32_t seed,
                                                        uint32_t initialAdvances,
                                                        uint32_t maxAdvances,
                                                        uint32_t offset,
                                                        uint8_t method,
                                                        int staticType,
                                                        int staticIndex,
                                                        uint16_t tid, uint16_t sid,
                                                        uint32_t game,
                                                        uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                        const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                        const bool natures[25], const bool powers[16],
                                                        int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate3 *tmpl = Encounters3::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeGenerator generator(initialAdvances, maxAdvances, offset, static_cast<Method>(method), false, profile, filter);
    auto results = generator.generate(seed, tmpl);

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState *>(malloc(sizeof(PFGeneratorState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState(results[i]);
    }
    return out;
}

// MARK: - GameCube Searcher (Shadow)

extern "C" PFSearcherState *pf_gamecubeSearchShadow(uint8_t method, bool unset,
                                                      uint16_t tid, uint16_t sid, uint32_t game,
                                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                      const bool natures[25], const bool powers[16],
                                                      int shadowIndex,
                                                      int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const ShadowTemplate *tmpl = Encounters3::getShadowTeam(shadowIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeSearcher searcher(static_cast<Method>(method), unset, profile, filter);
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());
    searcher.startSearch(min, max, tmpl);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState *>(malloc(sizeof(PFSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState(results[i]);
    }
    return out;
}

// MARK: - GameCube Searcher (Static)

extern "C" PFSearcherState *pf_gamecubeSearchStatic(uint8_t method, bool unset,
                                                      uint16_t tid, uint16_t sid, uint32_t game,
                                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                      const bool natures[25], const bool powers[16],
                                                      int staticType, int staticIndex,
                                                      int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate3 *tmpl = Encounters3::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    GameCubeSearcher searcher(static_cast<Method>(method), unset, profile, filter);
    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());
    searcher.startSearch(min, max, tmpl);

    auto results = searcher.getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearcherState *>(malloc(sizeof(PFSearcherState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchState(results[i]);
    }
    return out;
}

// MARK: - PokeSpot Generator

extern "C" PFPokeSpotState *pf_pokeSpotGenerate(uint32_t seedFood, uint32_t seedEncounter,
                                                  uint32_t initialAdvances, uint32_t maxAdvances, uint32_t offset,
                                                  uint32_t initialAdvancesEncounter, uint32_t maxAdvancesEncounter, uint32_t offsetEncounter,
                                                  uint16_t tid, uint16_t sid, uint32_t game,
                                                  int pokeSpotIndex,
                                                  uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                  const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                  const bool natures[25], const bool powers[16],
                                                  const bool encounterSlots[12],
                                                  int *outCount)
{
    Profile3 profile("-", static_cast<Game>(game), tid, sid, false);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    auto areas = Encounters3::getPokeSpotEncounters();
    if (pokeSpotIndex < 0 || pokeSpotIndex >= static_cast<int>(areas.size())) {
        *outCount = 0;
        return nullptr;
    }

    PokeSpotGenerator generator(initialAdvances, maxAdvances, offset,
                                 initialAdvancesEncounter, maxAdvancesEncounter, offsetEncounter,
                                 profile, filter);
    auto results = generator.generate(seedFood, seedEncounter, areas[pokeSpotIndex]);

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFPokeSpotState *>(malloc(sizeof(PFPokeSpotState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].advances = s.getAdvances();
        out[i].encounterAdvances = s.getEncounterAdvances();
        out[i].pid = s.getPID();
        auto ivs = s.getIVs();
        for (int j = 0; j < 6; j++) out[i].ivs[j] = ivs[j];
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].hiddenPower = s.getHiddenPower();
        out[i].hiddenPowerStrength = s.getHiddenPowerStrength();
        out[i].encounterSlot = s.getEncounterSlot();
        out[i].level = s.getLevel();
        out[i].specie = s.getSpecie();
    }
    return out;
}

extern "C" PFEncounterArea *pf_getPokeSpotEncounters(int *outCount)
{
    auto areas = Encounters3::getPokeSpotEncounters();
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i].location = areas[i].getLocation();
        out[i].rate = areas[i].getRate();
        out[i].encounter = static_cast<uint8_t>(areas[i].getEncounter());
        auto pokemon = areas[i].getPokemon();
        out[i].slotCount = static_cast<int>(pokemon.size());
        for (size_t j = 0; j < pokemon.size() && j < 12; j++) {
            out[i].slots[j].specie = pokemon[j].getSpecie();
            out[i].slots[j].form = pokemon[j].getForm();
            out[i].slots[j].minLevel = pokemon[j].getMinLevel();
            out[i].slots[j].maxLevel = pokemon[j].getMaxLevel();
        }
    }
    return out;
}

// MARK: - Seed Searchers (GameCube) - Async

// The seed searchers count each seed they try but have no total of their
// own, so the start functions set one. Their results land when each worker
// thread finishes and are sorted, unlocked, at the end, so read them once
// the search is done.
struct PFSeedSearch {
    std::variant<ColoSeedSearcher *, GalesSeedSearcher *, ChannelSeedSearcher *> searcher;
    std::thread thread;
    int type; // 0=colo, 1=gales, 2=channel
    std::atomic<bool> done { false };

    ~PFSeedSearch() {
        if (thread.joinable()) thread.join();
        switch (type) {
            case 0: delete std::get<ColoSeedSearcher *>(searcher); break;
            case 1: delete std::get<GalesSeedSearcher *>(searcher); break;
            case 2: delete std::get<ChannelSeedSearcher *>(searcher); break;
        }
    }
};

extern "C" PFSeedSearchHandle pf_coloSeedSearch_start(uint8_t lead, uint8_t trainer, int threads)
{
    ColoCriteria criteria;
    criteria.lead = lead;
    criteria.trainer = trainer;

    auto *s = new ColoSeedSearcher(criteria);
    // Every low half of the seed (0x10000).
    s->setMaxProgress(0x10000);
    auto *handle = new PFSeedSearch();
    handle->searcher = s;
    handle->type = 0;
    handle->thread = std::thread([handle, s, threads]() {
        s->startSearch(threads);
        handle->done = true;
    });
    return handle;
}

extern "C" PFSeedSearchHandle pf_galesSeedSearch_start(uint16_t enemyHP0, uint16_t enemyHP1,
                                                         uint16_t playerHP0, uint16_t playerHP1,
                                                         uint8_t enemyIndex, uint8_t playerIndex,
                                                         int threads)
{
    GalesCriteria criteria;
    criteria.enemyHP[0] = enemyHP0;
    criteria.enemyHP[1] = enemyHP1;
    criteria.playerHP[0] = playerHP0;
    criteria.playerHP[1] = playerHP1;
    criteria.enemyIndex = enemyIndex;
    criteria.playerIndex = playerIndex;

    auto *s = new GalesSeedSearcher(criteria);
    // Every low half of the seed (0x10000).
    s->setMaxProgress(0x10000);
    auto *handle = new PFSeedSearch();
    handle->searcher = s;
    handle->type = 1;
    handle->thread = std::thread([handle, s, threads]() {
        s->startSearch(threads);
        handle->done = true;
    });
    return handle;
}

extern "C" PFSeedSearchHandle pf_channelSeedSearch_start(const uint8_t *pattern, int patternLength, int threads)
{
    std::vector<u8> criteria(pattern, pattern + patternLength);

    auto *s = new ChannelSeedSearcher(criteria);
    // 0x40000001 to 0xFFFFFFFF.
    s->setMaxProgress(0xbffffffe);
    auto *handle = new PFSeedSearch();
    handle->searcher = s;
    handle->type = 2;
    handle->thread = std::thread([handle, s, threads]() {
        s->startSearch(threads);
        handle->done = true;
    });
    return handle;
}

extern "C" int pf_seedSearch_progress(PFSeedSearchHandle h)
{
    auto *handle = static_cast<PFSeedSearch *>(h);
    switch (handle->type) {
        case 0: return std::get<ColoSeedSearcher *>(handle->searcher)->getProgress();
        case 1: return std::get<GalesSeedSearcher *>(handle->searcher)->getProgress();
        case 2: return std::get<ChannelSeedSearcher *>(handle->searcher)->getProgress();
    }
    return 0;
}

extern "C" bool pf_seedSearch_done(PFSeedSearchHandle h)
{
    return static_cast<PFSeedSearch *>(h)->done;
}

extern "C" uint32_t *pf_seedSearch_getResults(PFSeedSearchHandle h, int *outCount)
{
    auto *handle = static_cast<PFSeedSearch *>(h);
    std::vector<u32> results;
    switch (handle->type) {
        case 0: results = std::get<ColoSeedSearcher *>(handle->searcher)->getResults(); break;
        case 1: results = std::get<GalesSeedSearcher *>(handle->searcher)->getResults(); break;
        case 2: results = std::get<ChannelSeedSearcher *>(handle->searcher)->getResults(); break;
    }

    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<uint32_t *>(malloc(sizeof(uint32_t) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = results[i];
    }
    return out;
}

extern "C" void pf_seedSearch_cancel(PFSeedSearchHandle h)
{
    auto *handle = static_cast<PFSeedSearch *>(h);
    switch (handle->type) {
        case 0: std::get<ColoSeedSearcher *>(handle->searcher)->cancelSearch(); break;
        case 1: std::get<GalesSeedSearcher *>(handle->searcher)->cancelSearch(); break;
        case 2: std::get<ChannelSeedSearcher *>(handle->searcher)->cancelSearch(); break;
    }
}

extern "C" void pf_seedSearch_free(PFSeedSearchHandle h)
{
    auto *handle = static_cast<PFSeedSearch *>(h);
    delete handle;
}

// MARK: - XD/Colo ID Generator

extern "C" PFIDState *pf_idGenerate3_XDColo(uint32_t seed,
                                              uint32_t initialAdvances, uint32_t maxAdvances,
                                              int *outCount)
{
    IDFilter filter({}, {}, {}, {}, {}, {});
    IDGenerator3 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generateXDColo(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState *>(malloc(sizeof(PFIDState) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - Jirachi Pattern

extern "C" uint8_t *pf_jirachiPattern(uint32_t seed, uint32_t targetAdvance, uint32_t bruteForce, int *outCount)
{
    auto actions = JirachiPattern::calculateActions(seed, targetAdvance, bruteForce);
    *outCount = static_cast<int>(actions.size());
    if (actions.empty()) return nullptr;

    auto *out = static_cast<uint8_t *>(malloc(sizeof(uint8_t) * actions.size()));
    for (size_t i = 0; i < actions.size(); i++) {
        out[i] = actions[i];
    }
    return out;
}

extern "C" uint32_t pf_computeJirachiSeed(uint32_t seed)
{
    return JirachiPattern::computeJirachiSeed(seed);
}

// MARK: - Seed Verification Tools (Gen 4)

extern "C" char *pf_coinFlips(uint32_t seed)
{
    std::string result = Utilities4::coinFlips(seed);
    return copyString(result);
}

extern "C" char *pf_getCalls(uint32_t seed, uint8_t skips)
{
    std::string result = Utilities4::getCalls(seed, skips);
    return copyString(result);
}

// MARK: - Gen 5 Helpers

static Profile5 makeProfile5(Game game, u16 tid, u16 sid,
                               u64 mac, const bool keypresses[9],
                               u8 vcount, u8 gxstat, u8 vframe,
                               bool skipLR, u16 timer0Min, u16 timer0Max,
                               bool memoryLink, bool shinyCharm,
                               u8 dsType, u8 language)
{
    std::array<bool, 9> kp;
    std::copy(keypresses, keypresses + 9, kp.begin());
    return Profile5("-", game, tid, sid, "", "", mac, kp, vcount, gxstat, vframe,
                    skipLR, timer0Min, timer0Max, memoryLink, shinyCharm,
                    static_cast<DSType>(dsType), static_cast<Language>(language));
}

static PFGeneratorState5 convertGenState5(const State5 &s)
{
    PFGeneratorState5 r;
    r.advances = s.getAdvances();
    r.ivAdvances = s.getIVAdvances();
    r.pid = s.getPID();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.chatot = s.getChatot();
    return r;
}

static PFWildGeneratorState5 convertWildGenState5(const WildState5 &s)
{
    PFWildGeneratorState5 r;
    r.advances = s.getAdvances();
    r.ivAdvances = s.getIVAdvances();
    r.pid = s.getPID();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    r.chatot = s.getChatot();
    return r;
}

static EncounterArea5 findEncounterArea5(Encounter encounter, u8 season,
                                          const Profile5 &profile, uint8_t location)
{
    auto areas = Encounters5::getEncounters(encounter, season, &profile);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea5(0, 0, false, Encounter::Grass, {});
}

// MARK: - Gen 5 Static Generator

extern "C" PFGeneratorState5 *pf_staticGenerate5(uint64_t seed,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint32_t ivInitialAdvances, uint32_t ivMaxAdvances,
                                                    uint8_t method,
                                                    uint8_t lead,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    int staticType, int staticIndex,
                                                    uint64_t mac, const bool keypresses[9],
                                                    uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                    bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                    bool memoryLink, bool shinyCharm,
                                                    uint8_t dsType, uint8_t language,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate5 *tmpl = Encounters5::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    StaticGenerator5 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Method>(method), static_cast<Lead>(lead),
                                0, *tmpl, profile, filter);

    // PokéFinder pairs each PID advance with each IV advance, so the IVs
    // get their own range; the PID range there made (n + 1)² results.
    auto results = generator.generate(seed, ivInitialAdvances, ivMaxAdvances);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState5 *>(malloc(sizeof(PFGeneratorState5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState5(results[i]);
    }
    return out;
}

// MARK: - Gen 5 Wild Generator

extern "C" PFWildGeneratorState5 *pf_wildGenerate5(uint64_t seed,
                                                      uint32_t initialAdvances,
                                                      uint32_t maxAdvances,
                                                      uint32_t offset,
                                                      uint32_t ivInitialAdvances, uint32_t ivMaxAdvances,
                                                      uint8_t method,
                                                      uint8_t lead,
                                                      uint16_t tid, uint16_t sid,
                                                      uint32_t game,
                                                      uint8_t encounter, uint8_t location,
                                                      uint8_t season,
                                                      uint64_t mac, const bool keypresses[9],
                                                      uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                      bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                      bool memoryLink, bool shinyCharm,
                                                      uint8_t dsType, uint8_t language,
                                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                      const bool natures[25], const bool powers[16],
                                                      const bool encounterSlots[12],
                                                      int *outCount)
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterArea5 area = findEncounterArea5(static_cast<Encounter>(encounter), season,
                                              profile, location);

    WildGenerator5 generator(initialAdvances, maxAdvances, offset,
                              static_cast<Method>(method), static_cast<Lead>(lead),
                              0, area, profile, filter);

    // Each PID advance pairs with each IV advance, as the static one.
    auto results = generator.generate(seed, ivInitialAdvances, ivMaxAdvances);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState5 *>(malloc(sizeof(PFWildGeneratorState5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState5(results[i]);
    }
    return out;
}

// MARK: - Gen 5 Encounter Data

extern "C" PFEncounterArea *pf_getEncounters5(uint8_t encounter, uint32_t game,
                                                uint8_t season,
                                                uint16_t tid, uint16_t sid,
                                                uint64_t mac, const bool keypresses[9],
                                                uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                bool memoryLink, bool shinyCharm,
                                                uint8_t dsType, uint8_t language,
                                                int *outCount)
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);

    auto areas = Encounters5::getEncounters(static_cast<Encounter>(encounter), season, &profile);
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters5(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate5 *templates = Encounters5::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
        out[i].method = 0;
        out[i].ivCount = templates[i].getIVCount();
    }
    return out;
}

// MARK: - Gen 5 Egg Generator

extern "C" PFEggGeneratorState5 *pf_eggGenerate5(uint64_t seed,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                                    uint8_t parentAAbility, uint8_t parentBAbility,
                                                    uint8_t parentAGender, uint8_t parentBGender,
                                                    uint8_t parentAItem, uint8_t parentBItem,
                                                    uint8_t parentANature, uint8_t parentBNature,
                                                    uint16_t eggSpecie, bool masuda,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    uint64_t mac, const bool keypresses[9],
                                                    uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                    bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                    bool memoryLink, bool shinyCharm,
                                                    uint8_t dsType, uint8_t language,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator5 generator(initialAdvances, maxAdvances, offset, daycare, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState5 *>(malloc(sizeof(PFEggGeneratorState5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
        out[i].chatot = s.getChatot();
    }
    return out;
}

// MARK: - Gen 5 ID Generator

extern "C" PFIDState5 *pf_idGenerate5(uint64_t seed,
                                         uint32_t initialAdvances,
                                         uint32_t maxAdvances,
                                         uint32_t pid, bool checkPID, bool checkXOR,
                                         uint16_t tid, uint16_t sid,
                                         uint32_t game,
                                         uint64_t mac, const bool keypresses[9],
                                         uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                         bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                         bool memoryLink, bool shinyCharm,
                                         uint8_t dsType, uint8_t language,
                                         uint16_t filterTID, bool hasTIDFilter,
                                         uint16_t filterSID, bool hasSIDFilter,
                                         int *outCount)
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);

    std::vector<u16> tidVec;
    std::vector<u16> sidVec;
    if (hasTIDFilter) tidVec.push_back(filterTID);
    if (hasSIDFilter) sidVec.push_back(filterSID);

    IDFilter filter(tidVec, sidVec, {}, {}, {}, {});
    IDGenerator5 generator(initialAdvances, maxAdvances, pid, checkPID, checkXOR, profile, filter);

    auto results = generator.generate(seed);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState5 *>(malloc(sizeof(PFIDState5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
    }
    return out;
}

// MARK: - Gen 5 Async Searcher

struct PFAsyncSearch5 {
    enum class Type { Static, Wild } type;
    void *searcher;
    std::thread thread;

    ~PFAsyncSearch5() {
        if (thread.joinable()) thread.join();
        if (type == Type::Static)
            delete static_cast<IVSearcher5<StaticGenerator5, State5> *>(searcher);
        else
            delete static_cast<IVSearcher5<WildGenerator5, WildState5> *>(searcher);
    }
};

static PFSearchResult5 convertSearchResult5(const SearcherState5<State5> &s)
{
    PFSearchResult5 r;
    r.dateTime = convertDateTime(s.getDateTime());
    r.initialSeed = s.getInitialSeed();
    r.timer0 = s.getTimer0();
    r.buttons = static_cast<uint16_t>(s.getButtons());
    auto &st = s.getState();
    r.advances = st.getAdvances();
    r.ivAdvances = st.getIVAdvances();
    r.pid = st.getPID();
    auto ivs = st.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = st.getNature();
    r.ability = st.getAbility();
    r.gender = st.getGender();
    r.shiny = st.getShiny();
    r.hiddenPower = st.getHiddenPower();
    r.hiddenPowerStrength = st.getHiddenPowerStrength();
    r.chatot = st.getChatot();
    return r;
}

static PFWildSearchResult5 convertWildSearchResult5(const SearcherState5<WildState5> &s)
{
    PFWildSearchResult5 r;
    r.dateTime = convertDateTime(s.getDateTime());
    r.initialSeed = s.getInitialSeed();
    r.timer0 = s.getTimer0();
    r.buttons = static_cast<uint16_t>(s.getButtons());
    auto &st = s.getState();
    r.advances = st.getAdvances();
    r.ivAdvances = st.getIVAdvances();
    r.pid = st.getPID();
    auto ivs = st.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = st.getNature();
    r.ability = st.getAbility();
    r.gender = st.getGender();
    r.shiny = st.getShiny();
    r.hiddenPower = st.getHiddenPower();
    r.hiddenPowerStrength = st.getHiddenPowerStrength();
    r.encounterSlot = st.getEncounterSlot();
    r.level = st.getLevel();
    r.item = st.getItem();
    r.specie = st.getSpecie();
    r.form = st.getForm();
    r.chatot = st.getChatot();
    return r;
}

extern "C" PFSearch5Handle pf_staticSearch5_start(uint32_t initialAdvances, uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint8_t method, uint8_t lead,
                                                    uint16_t tid, uint16_t sid, uint32_t game,
                                                    int staticType, int staticIndex,
                                                    uint32_t ivInitialAdvances, uint32_t ivMaxAdvances,
                                                    uint64_t mac, const bool keypresses[9],
                                                    uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                    bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                    bool memoryLink, bool shinyCharm,
                                                    uint8_t dsType, uint8_t language,
                                                    uint16_t startYear, uint8_t startMonth, uint8_t startDay,
                                                    uint16_t endYear, uint8_t endMonth, uint8_t endDay,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16])
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate5 *tmpl = Encounters5::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) return nullptr;

    StaticGenerator5 gen(initialAdvances, maxAdvances, offset,
                          static_cast<Method>(method), static_cast<Lead>(lead),
                          0, *tmpl, profile, filter);

    auto *searcher = new IVSearcher5<StaticGenerator5, State5>(
        ivInitialAdvances, ivMaxAdvances, gen, profile);

    Date start(startYear, startMonth, startDay);
    Date end(endYear, endMonth, endDay);
    searcher->setMaxProgress(searcher->getMaxProgress(start, end));

    auto *handle = new PFAsyncSearch5();
    handle->type = PFAsyncSearch5::Type::Static;
    handle->searcher = searcher;
    handle->thread = std::thread([searcher, start, end]() {
        int threads = std::max(1u, std::thread::hardware_concurrency());
        searcher->startSearch(threads, start, end);
    });

    return static_cast<PFSearch5Handle>(handle);
}

extern "C" PFSearch5Handle pf_wildSearch5_start(uint32_t initialAdvances, uint32_t maxAdvances,
                                                  uint32_t offset,
                                                  uint8_t method, uint8_t lead,
                                                  uint16_t tid, uint16_t sid, uint32_t game,
                                                  uint8_t encounter, uint8_t location, uint8_t season,
                                                  uint32_t ivInitialAdvances, uint32_t ivMaxAdvances,
                                                  uint64_t mac, const bool keypresses[9],
                                                  uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                                  bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                                  bool memoryLink, bool shinyCharm,
                                                  uint8_t dsType, uint8_t language,
                                                  uint16_t startYear, uint8_t startMonth, uint8_t startDay,
                                                  uint16_t endYear, uint8_t endMonth, uint8_t endDay,
                                                  uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                  const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                  const bool natures[25], const bool powers[16],
                                                  const bool encounterSlots[12])
{
    Profile5 profile = makeProfile5(static_cast<Game>(game), tid, sid,
                                     mac, keypresses, vcount, gxstat, vframe,
                                     skipLR, timer0Min, timer0Max,
                                     memoryLink, shinyCharm, dsType, language);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterArea5 area = findEncounterArea5(static_cast<Encounter>(encounter), season,
                                              profile, location);

    WildGenerator5 gen(initialAdvances, maxAdvances, offset,
                        static_cast<Method>(method), static_cast<Lead>(lead),
                        0, area, profile, filter);

    auto *searcher = new IVSearcher5<WildGenerator5, WildState5>(
        ivInitialAdvances, ivMaxAdvances, gen, profile);

    Date start(startYear, startMonth, startDay);
    Date end(endYear, endMonth, endDay);
    searcher->setMaxProgress(searcher->getMaxProgress(start, end));

    auto *handle = new PFAsyncSearch5();
    handle->type = PFAsyncSearch5::Type::Wild;
    handle->searcher = searcher;
    handle->thread = std::thread([searcher, start, end]() {
        int threads = std::max(1u, std::thread::hardware_concurrency());
        searcher->startSearch(threads, start, end);
    });

    return static_cast<PFSearch5Handle>(handle);
}

extern "C" int pf_search5_progress(PFSearch5Handle handle)
{
    auto *h = static_cast<PFAsyncSearch5 *>(handle);
    if (h->type == PFAsyncSearch5::Type::Static)
        return static_cast<IVSearcher5<StaticGenerator5, State5> *>(h->searcher)->getProgress();
    return static_cast<IVSearcher5<WildGenerator5, WildState5> *>(h->searcher)->getProgress();
}

extern "C" PFSearchResult5 *pf_search5_static_getResults(PFSearch5Handle handle, int *outCount)
{
    auto *searcher = static_cast<IVSearcher5<StaticGenerator5, State5> *>(
        static_cast<PFAsyncSearch5 *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFSearchResult5 *>(malloc(sizeof(PFSearchResult5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertSearchResult5(results[i]);
    }
    return out;
}

extern "C" PFWildSearchResult5 *pf_search5_wild_getResults(PFSearch5Handle handle, int *outCount)
{
    auto *searcher = static_cast<IVSearcher5<WildGenerator5, WildState5> *>(
        static_cast<PFAsyncSearch5 *>(handle)->searcher);
    auto results = searcher->getResults();
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildSearchResult5 *>(malloc(sizeof(PFWildSearchResult5) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildSearchResult5(results[i]);
    }
    return out;
}

extern "C" void pf_search5_cancel(PFSearch5Handle handle)
{
    auto *h = static_cast<PFAsyncSearch5 *>(handle);
    if (h->type == PFAsyncSearch5::Type::Static)
        static_cast<IVSearcher5<StaticGenerator5, State5> *>(h->searcher)->cancelSearch();
    else
        static_cast<IVSearcher5<WildGenerator5, WildState5> *>(h->searcher)->cancelSearch();
}

extern "C" void pf_search5_free(PFSearch5Handle handle)
{
    delete static_cast<PFAsyncSearch5 *>(handle);
}

// MARK: - Gen 8 Helpers

static PFGeneratorState8 convertGenState8(const State8 &s)
{
    PFGeneratorState8 r;
    r.ec = s.getEC();
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.height = s.getHeight();
    r.weight = s.getWeight();
    r.level = s.getLevel();
    return r;
}

static PFWildGeneratorState8 convertWildGenState8(const WildState8 &s)
{
    PFWildGeneratorState8 r;
    r.ec = s.getEC();
    r.pid = s.getPID();
    r.advances = s.getAdvances();
    auto ivs = s.getIVs();
    for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
    r.nature = s.getNature();
    r.ability = s.getAbility();
    r.gender = s.getGender();
    r.shiny = s.getShiny();
    r.hiddenPower = s.getHiddenPower();
    r.hiddenPowerStrength = s.getHiddenPowerStrength();
    r.height = s.getHeight();
    r.weight = s.getWeight();
    r.encounterSlot = s.getEncounterSlot();
    r.level = s.getLevel();
    r.item = s.getItem();
    r.specie = s.getSpecie();
    r.form = s.getForm();
    return r;
}

static EncounterArea8 findEncounterArea8(Encounter encounter, const EncounterSettings8 &settings,
                                          const Profile8 &profile, uint8_t location)
{
    auto areas = Encounters8::getEncounters(encounter, settings, &profile);
    for (const auto &area : areas) {
        if (area.getLocation() == location) {
            return area;
        }
    }
    if (!areas.empty()) return areas[0];
    return EncounterArea8(0, 0, Encounter::Grass, {});
}

// MARK: - Gen 8 Static Generator

extern "C" PFGeneratorState8 *pf_staticGenerate8(uint64_t seed0, uint64_t seed1,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint8_t lead,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                    int staticType, int staticIndex,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const StaticTemplate8 *tmpl = Encounters8::getStaticEncounter(staticType, staticIndex);
    if (!tmpl) { *outCount = 0; return nullptr; }

    StaticGenerator8 generator(initialAdvances, maxAdvances, offset,
                                static_cast<Lead>(lead), *tmpl, profile, filter);

    auto results = generator.generate(seed0, seed1);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState8 *>(malloc(sizeof(PFGeneratorState8) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState8(results[i]);
    }
    return out;
}

// MARK: - Gen 8 Wild Generator

extern "C" PFWildGeneratorState8 *pf_wildGenerate8(uint64_t seed0, uint64_t seed1,
                                                      uint32_t initialAdvances,
                                                      uint32_t maxAdvances,
                                                      uint32_t offset,
                                                      uint8_t lead,
                                                      uint16_t tid, uint16_t sid,
                                                      uint32_t game,
                                                      bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                      uint8_t encounter, uint8_t location,
                                                      int time, bool swarm, bool radar,
                                                      uint16_t replacement0, uint16_t replacement1,
                                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                      const bool natures[25], const bool powers[16],
                                                      const bool encounterSlots[12],
                                                      int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);
    WildStateFilter filter = makeWildFilter(filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, encounterSlots);

    EncounterSettings8 settings;
    settings.time = time;
    settings.swarm = swarm;
    settings.radar = radar;
    settings.replacement = { replacement0, replacement1 };

    EncounterArea8 area = findEncounterArea8(static_cast<Encounter>(encounter), settings,
                                              profile, location);

    WildGenerator8 generator(initialAdvances, maxAdvances, offset,
                              Method::None, static_cast<Lead>(lead),
                              area, profile, filter);

    auto results = generator.generate(seed0, seed1, 0);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFWildGeneratorState8 *>(malloc(sizeof(PFWildGeneratorState8) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertWildGenState8(results[i]);
    }
    return out;
}

// MARK: - Gen 8 Egg Generator

extern "C" PFEggGeneratorState8 *pf_eggGenerate8(uint64_t seed0, uint64_t seed1,
                                                    uint32_t initialAdvances,
                                                    uint32_t maxAdvances,
                                                    uint32_t offset,
                                                    uint8_t compatibility,
                                                    const uint8_t parentAIVs[6], const uint8_t parentBIVs[6],
                                                    uint8_t parentAAbility, uint8_t parentBAbility,
                                                    uint8_t parentAGender, uint8_t parentBGender,
                                                    uint8_t parentAItem, uint8_t parentBItem,
                                                    uint8_t parentANature, uint8_t parentBNature,
                                                    uint16_t eggSpecie, bool masuda,
                                                    uint16_t tid, uint16_t sid,
                                                    uint32_t game,
                                                    bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                    uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                    const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                    const bool natures[25], const bool powers[16],
                                                    int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    std::array<std::array<u8, 6>, 2> parentIVs;
    std::copy(parentAIVs, parentAIVs + 6, parentIVs[0].begin());
    std::copy(parentBIVs, parentBIVs + 6, parentIVs[1].begin());

    std::array<u8, 2> abilities = { parentAAbility, parentBAbility };
    std::array<u8, 2> genders = { parentAGender, parentBGender };
    std::array<u8, 2> items = { parentAItem, parentBItem };
    std::array<u8, 2> dcNatures = { parentANature, parentBNature };

    Daycare daycare(parentIVs, abilities, genders, items, dcNatures, eggSpecie, masuda);

    EggGenerator8 generator(initialAdvances, maxAdvances, offset, compatibility, daycare, profile, filter);

    auto results = generator.generate(seed0, seed1);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFEggGeneratorState8 *>(malloc(sizeof(PFEggGeneratorState8) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        auto &s = results[i];
        out[i].ec = s.getEC();
        out[i].pid = s.getPID();
        out[i].advances = s.getAdvances();
        out[i].seed = s.getSeed();
        auto ivs = s.getIVs();
        auto inh = s.getInheritance();
        for (int j = 0; j < 6; j++) {
            out[i].ivs[j] = ivs[j];
            out[i].inheritance[j] = inh[j];
        }
        out[i].nature = s.getNature();
        out[i].ability = s.getAbility();
        out[i].gender = s.getGender();
        out[i].shiny = s.getShiny();
    }
    return out;
}

// MARK: - Gen 8 ID Generator

extern "C" PFIDState8 *pf_idGenerate8(uint64_t seed0, uint64_t seed1,
                                         uint32_t initialAdvances, uint32_t maxAdvances,
                                         uint16_t filterTID, bool hasTIDFilter,
                                         uint16_t filterSID, bool hasSIDFilter,
                                         uint32_t filterDisplayTID, bool hasDisplayFilter,
                                         int *outCount)
{
    std::vector<u16> tidVec;
    std::vector<u16> sidVec;
    std::vector<u32> displayVec;
    if (hasTIDFilter) tidVec.push_back(filterTID);
    if (hasSIDFilter) sidVec.push_back(filterSID);
    if (hasDisplayFilter) displayVec.push_back(filterDisplayTID);

    IDFilter filter(tidVec, sidVec, {}, {}, {}, displayVec);
    IDGenerator8 generator(initialAdvances, maxAdvances, filter);

    auto results = generator.generate(seed0, seed1);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFIDState8 *>(malloc(sizeof(PFIDState8) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i].advances = results[i].getAdvances();
        out[i].tid = results[i].getTID();
        out[i].sid = results[i].getSID();
        out[i].tsv = results[i].getTSV();
        out[i].displayTID = results[i].getDisplayTID();
    }
    return out;
}

// MARK: - Gen 8 Raid Generator

extern "C" PFGeneratorState8 *pf_raidGenerate8(uint64_t seed,
                                                  uint32_t initialAdvances,
                                                  uint32_t maxAdvances,
                                                  uint32_t offset,
                                                  uint16_t tid, uint16_t sid,
                                                  uint32_t game,
                                                  bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                  uint16_t denIndex, uint8_t rarity,
                                                  uint8_t raidIndex, uint8_t level,
                                                  uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                  const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                  const bool natures[25], const bool powers[16],
                                                  int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);
    StateFilter filter = makeFilter(filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers);

    const Den *den = Encounters8::getDen(denIndex, rarity);
    if (!den) { *outCount = 0; return nullptr; }

    Raid raid = den->getRaid(raidIndex, static_cast<Game>(game));

    RaidGenerator generator(initialAdvances, maxAdvances, offset, profile, filter);

    auto results = generator.generate(seed, level, raid);
    *outCount = static_cast<int>(results.size());
    if (results.empty()) return nullptr;

    auto *out = static_cast<PFGeneratorState8 *>(malloc(sizeof(PFGeneratorState8) * results.size()));
    for (size_t i = 0; i < results.size(); i++) {
        out[i] = convertGenState8(results[i]);
    }
    return out;
}

// MARK: - Gen 8 Underground Generator

extern "C" PFUndergroundState *pf_undergroundGenerate8(uint64_t seed0, uint64_t seed1,
                                                         uint32_t initialAdvances,
                                                         uint32_t maxAdvances,
                                                         uint32_t offset,
                                                         uint8_t lead,
                                                         bool diglett, uint8_t levelFlag,
                                                         uint16_t tid, uint16_t sid,
                                                         uint32_t game,
                                                         bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                         int storyFlag,
                                                         uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                         const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                         const bool natures[25], const bool powers[16],
                                                         int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);

    std::array<u8, 6> min, max;
    std::copy(ivMin, ivMin + 6, min.begin());
    std::copy(ivMax, ivMax + 6, max.begin());

    auto natArr = allowedOrAll<25>(natures);
    auto powArr = allowedOrAll<16>(powers);

    auto undergroundAreas = Encounters8::getUndergroundEncounters(storyFlag, diglett, &profile);
    if (undergroundAreas.empty()) { *outCount = 0; return nullptr; }

    // The filter also checks the species against this list, so it holds
    // every one the areas can give.
    std::vector<u16> species;
    for (const auto &area : undergroundAreas) {
        auto areaSpecies = area.getSpecies();
        species.insert(species.end(), areaSpecies.begin(), areaSpecies.end());
    }
    bool skip = filtersNothing(filterGender, filterAbility, filterShiny, min, max, natArr, powArr);
    UndergroundStateFilter filter(filterGender, filterAbility, filterShiny, 0, 255, 0, 255,
                                   skip, min, max, natArr, powArr, species);

    std::vector<PFUndergroundState> allResults;

    for (const auto &area : undergroundAreas) {
        UndergroundGenerator generator(initialAdvances, maxAdvances, offset,
                                        static_cast<Lead>(lead), diglett, levelFlag,
                                        area, profile, filter);

        auto results = generator.generate(seed0, seed1);
        for (const auto &s : results) {
            PFUndergroundState r;
            r.ec = s.getEC();
            r.pid = s.getPID();
            r.advances = s.getAdvances();
            auto ivs = s.getIVs();
            for (int i = 0; i < 6; i++) r.ivs[i] = ivs[i];
            r.nature = s.getNature();
            r.ability = s.getAbility();
            r.gender = s.getGender();
            r.shiny = s.getShiny();
            r.hiddenPower = s.getHiddenPower();
            r.hiddenPowerStrength = s.getHiddenPowerStrength();
            r.height = s.getHeight();
            r.weight = s.getWeight();
            r.eggMove = s.getEggMove();
            r.item = s.getItem();
            r.specie = s.getSpecie();
            r.level = s.getLevel();
            allResults.push_back(r);
        }
    }

    *outCount = static_cast<int>(allResults.size());
    if (allResults.empty()) return nullptr;

    auto *out = static_cast<PFUndergroundState *>(malloc(sizeof(PFUndergroundState) * allResults.size()));
    std::copy(allResults.begin(), allResults.end(), out);
    return out;
}

// MARK: - Gen 8 Encounter Data

extern "C" PFEncounterArea *pf_getEncounters8(uint8_t encounter, uint32_t game,
                                                uint16_t tid, uint16_t sid,
                                                bool nationalDex, bool shinyCharm, bool ovalCharm,
                                                int time, bool swarm, bool radar,
                                                uint16_t replacement0, uint16_t replacement1,
                                                int *outCount)
{
    Profile8 profile("-", static_cast<Game>(game), tid, sid, nationalDex, shinyCharm, ovalCharm);
    EncounterSettings8 settings;
    settings.time = time;
    settings.swarm = swarm;
    settings.radar = radar;
    settings.replacement = { replacement0, replacement1 };

    auto areas = Encounters8::getEncounters(static_cast<Encounter>(encounter), settings, &profile);
    *outCount = static_cast<int>(areas.size());
    if (areas.empty()) return nullptr;

    auto *out = static_cast<PFEncounterArea *>(malloc(sizeof(PFEncounterArea) * areas.size()));
    for (size_t i = 0; i < areas.size(); i++) {
        out[i] = convertEncounterArea(areas[i]);
    }
    return out;
}

extern "C" PFStaticTemplate *pf_getStaticEncounters8(int type, int *outCount)
{
    int size = 0;
    const StaticTemplate8 *templates = Encounters8::getStaticEncounters(type, &size);
    *outCount = size;
    if (size == 0 || templates == nullptr) return nullptr;

    auto *out = static_cast<PFStaticTemplate *>(malloc(sizeof(PFStaticTemplate) * size));
    for (int i = 0; i < size; i++) {
        out[i].game = static_cast<uint32_t>(templates[i].getVersion());
        out[i].specie = templates[i].getSpecie();
        out[i].form = templates[i].getForm();
        out[i].shiny = static_cast<uint8_t>(templates[i].getShiny());
        out[i].ability = templates[i].getAbility();
        out[i].gender = templates[i].getGender();
        out[i].level = templates[i].getLevel();
        out[i].method = 0;
        out[i].ivCount = templates[i].getIVCount();
    }
    return out;
}
