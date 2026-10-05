#ifndef PFBridge_h
#define PFBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Result Structs

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint16_t sid;
    uint8_t method; // maps to Method enum
} PFIVToPIDResult;

typedef struct {
    uint32_t seed;
    uint8_t ivs[6];
    uint8_t method;
} PFPIDToIVResult;

typedef struct {
    uint16_t originSeed;
    uint32_t advances;
} PFOriginSeed3;

typedef struct {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
} PFDateTime;

typedef struct {
    PFDateTime dateTime;
    uint32_t delay;
} PFSeedTime4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFGeneratorState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t call;
    uint8_t chatot;
} PFGeneratorState4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFSearcherState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
} PFSearcherState4;

// MARK: - Encounter Slot

typedef struct {
    uint16_t specie;
    uint8_t form;
    uint8_t minLevel;
    uint8_t maxLevel;
} PFSlot;

typedef struct {
    uint8_t location;
    uint8_t rate;
    uint8_t encounter;
    uint8_t slotCount;
    PFSlot slots[12];
} PFEncounterArea;

typedef struct {
    uint32_t game;
    uint16_t specie;
    uint8_t form;
    uint8_t shiny;
    uint8_t ability;
    uint8_t gender;
    uint8_t level;
    /// PokéFinder's Method; Gen 4 only (Method 1, J or K), else 0.
    uint8_t method;
    /// IVs fixed at 31 (BDSP legends' three).
    uint8_t ivCount;
} PFStaticTemplate;

// MARK: - Wild Generator State

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildGeneratorState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildSearcherState;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
    uint8_t call;
    uint8_t chatot;
} PFWildGeneratorState4;

typedef struct {
    uint32_t seed;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildSearcherState4;

// MARK: - Async Searcher Handle

typedef void *PFStaticSearch3Handle;

PFStaticSearch3Handle pf_staticSearch3_start(uint8_t method,
                                             uint16_t tid, uint16_t sid,
                                             uint32_t game,
                                             int staticType, int staticIndex,
                                             uint8_t gender, uint8_t ability, uint8_t shiny,
                                             const uint8_t ivMin[6], const uint8_t ivMax[6],
                                             const bool natures[25], const bool powers[16]);
int pf_staticSearch3_progress(PFStaticSearch3Handle handle);
bool pf_staticSearch3_done(PFStaticSearch3Handle handle);
PFSearcherState *pf_staticSearch3_getResults(PFStaticSearch3Handle handle, int *outCount);
void pf_staticSearch3_cancel(PFStaticSearch3Handle handle);
void pf_staticSearch3_free(PFStaticSearch3Handle handle);

typedef void *PFSearchHandle;

PFSearchHandle pf_wildSearch3_start(uint8_t method, uint8_t lead,
                                     uint16_t tid, uint16_t sid,
                                     uint32_t game, bool deadBattery, bool feebasTile,
                                     uint8_t encounter, uint8_t location,
                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                     const bool natures[25], const bool powers[16],
                                     const bool encounterSlots[12]);

PFSearchHandle pf_wildSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                     uint32_t minDelay, uint32_t maxDelay,
                                     uint8_t method, uint8_t lead,
                                     uint16_t tid, uint16_t sid,
                                     uint32_t game, bool feebasTile,
                                     uint8_t encounter, uint8_t location,
                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                     const bool natures[25], const bool powers[16],
                                     const bool encounterSlots[12]);

int pf_search_progress(PFSearchHandle handle);
PFWildSearcherState *pf_search3_getResults(PFSearchHandle handle, int *outCount);
PFWildSearcherState4 *pf_search4_getResults(PFSearchHandle handle, int *outCount);
void pf_search_cancel(PFSearchHandle handle);
void pf_search_free(PFSearchHandle handle);

// MARK: - Memory Management

void pf_freeResults(void *ptr);
void pf_freeString(char *str);
void pf_freeStringArray(char **arr, int count);

// MARK: - Tools

PFIVToPIDResult *pf_ivToPID(uint8_t hp, uint8_t atk, uint8_t def,
                             uint8_t spa, uint8_t spd, uint8_t spe,
                             uint8_t nature, uint16_t tid,
                             int *outCount);

PFPIDToIVResult *pf_pidToIV(uint32_t pid, int *outCount);

PFOriginSeed3 pf_seedToTimeOriginSeed3(uint32_t seed);

PFDateTime *pf_seedToTime3(uint32_t seed, uint16_t year, int *outCount);

PFSeedTime4 *pf_seedToTime4(uint32_t seed, uint16_t year,
                              bool forceSecond, uint8_t forcedSecond,
                              int *outCount);

// MARK: - Gen 3 Generators

PFGeneratorState *pf_staticGenerate3(uint32_t seed,
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
                                      int *outCount);

// MARK: - Gen 3 Searchers

PFSearcherState *pf_staticSearch3(uint8_t method,
                                   uint16_t tid, uint16_t sid,
                                   uint8_t game,
                                   bool deadBattery,
                                   uint8_t gender, uint8_t ability, uint8_t shiny,
                                   const uint8_t ivMin[6], const uint8_t ivMax[6],
                                   const bool natures[25], const bool powers[16],
                                   int *outCount);

// MARK: - Gen 4 Generators

PFGeneratorState4 *pf_staticGenerate4(uint32_t seed,
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
                                       int *outCount);

// MARK: - Gen 4 Searchers

typedef void *PFStaticSearch4Handle;

PFStaticSearch4Handle pf_staticSearch4_start(uint32_t minAdvance, uint32_t maxAdvance,
                                             uint32_t minDelay, uint32_t maxDelay,
                                             uint8_t method, uint8_t lead,
                                             int staticType, int staticIndex,
                                             uint16_t tid, uint16_t sid, uint32_t game,
                                             uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                             const uint8_t ivMin[6], const uint8_t ivMax[6],
                                             const bool natures[25], const bool powers[16]);
int pf_staticSearch4_progress(PFStaticSearch4Handle handle);
bool pf_staticSearch4_done(PFStaticSearch4Handle handle);
PFSearcherState4 *pf_staticSearch4_getResults(PFStaticSearch4Handle handle, int *outCount);
void pf_staticSearch4_cancel(PFStaticSearch4Handle handle);
void pf_staticSearch4_free(PFStaticSearch4Handle handle);

// MARK: - Translator

void pf_initTranslator(const char *locale);
char *pf_getSpecieName(uint16_t specie);
char *pf_getFormName(uint16_t specie, uint8_t form);
char *pf_getAbilityName(uint16_t ability);
char *pf_getNatureName(uint8_t nature);
char *pf_getHiddenPowerName(uint8_t power);
char *pf_getItemName(uint16_t item);
char *pf_getMoveName(uint16_t move);
char **pf_getNatureNames(int *outCount);
char **pf_getHiddenPowerNames(int *outCount);
char **pf_getLocationNames(const uint16_t *locationNums, int count, uint32_t game);

// MARK: - Encounter Data

PFEncounterArea *pf_getEncounters3(uint8_t encounter, uint32_t game,
                                    bool feebasTile, int *outCount);
PFEncounterArea *pf_getEncounters4(uint8_t encounter, uint32_t game,
                                    uint16_t tid, uint16_t sid,
                                    int time, bool swarm,
                                    uint32_t dual,
                                    uint16_t replacement0, uint16_t replacement1,
                                    bool feebasTile, bool radar,
                                    int radio,
                                    const uint8_t blocks[5],
                                    int *outCount);
PFStaticTemplate *pf_getStaticEncounters3(int type, int *outCount);
PFStaticTemplate *pf_getStaticEncounters4(int type, int *outCount);

// MARK: - Wild Generators

PFWildGeneratorState *pf_wildGenerate3(uint32_t seed,
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
                                        int *outCount);

PFWildSearcherState *pf_wildSearch3(uint8_t method,
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
                                     int *outCount);

PFWildGeneratorState4 *pf_wildGenerate4(uint32_t seed,
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
                                         int *outCount);

PFWildSearcherState4 *pf_wildSearch4(uint32_t minAdvance, uint32_t maxAdvance,
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
                                      int *outCount);

// MARK: - Egg Generator State

typedef struct {
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6]; // 0=random, 1=parent A, 2=parent B
    uint8_t redraws;
    uint32_t pickupAdvances;
} PFEggGeneratorState3;

typedef struct {
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6];
    uint32_t pickupAdvances;
    uint8_t call;
    uint8_t chatot;
} PFEggGeneratorState4;

// MARK: - ID Generator State

typedef struct {
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
} PFIDState;

typedef struct {
    uint32_t seed;
    uint32_t delay;
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
    uint8_t seconds;
} PFIDState4;

// MARK: - Egg Generators

PFEggGeneratorState3 *pf_eggGenerate3(uint32_t seedHeld, uint32_t seedPickup,
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
                                       int *outCount);

PFEggGeneratorState4 *pf_eggGenerate4(uint32_t seedHeld, uint32_t seedPickup,
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
                                       int *outCount);

// MARK: - ID Generators

PFIDState *pf_idGenerate3_RS(uint16_t seed,
                              uint32_t initialAdvances, uint32_t maxAdvances,
                              int *outCount);

PFIDState *pf_idGenerate3_FRLGE(uint16_t tid,
                                 uint32_t initialAdvances, uint32_t maxAdvances,
                                 int *outCount);

PFIDState4 *pf_idGenerate4(uint32_t minDelay, uint32_t maxDelay,
                             uint16_t year, uint8_t month, uint8_t day,
                             uint8_t hour, uint8_t minute,
                             uint16_t targetTID, bool filterTID,
                             uint16_t targetSID, bool filterSID,
                             int *outCount);

// MARK: - GameCube Shadow Template Info

typedef struct {
    uint16_t specie;
    uint8_t level;
    uint8_t shadowType;
    uint32_t game;
} PFShadowTemplateInfo;

PFShadowTemplateInfo *pf_getShadowTemplates(int *outCount);

// MARK: - GameCube Generator

PFGeneratorState *pf_gamecubeGenerateShadow(uint32_t seed,
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
                                             int *outCount);

PFGeneratorState *pf_staticTemplateGenerate3(uint32_t seed,
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
                                              int *outCount);

bool pf_calcIVsStatic3(int staticType, int staticIndex,
                       const uint8_t *levels, const uint16_t *stats, int count,
                       uint8_t nature, uint8_t outMin[6], uint8_t outMax[6]);

PFGeneratorState *pf_gamecubeGenerateStatic(uint32_t seed,
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
                                             int *outCount);

// MARK: - GameCube Searcher (Async)

/// A GameCube search on its own thread, as Gen 3's static searcher: poll
/// `_getResults` and `_progress` until `_done`, then `_free`.
typedef void *PFGameCubeSearchHandle;

/// A shadow Pokémon's search; NULL if `shadowIndex` isn't one.
PFGameCubeSearchHandle pf_gamecubeSearchShadow_start(uint8_t method, bool unset,
                                                     uint16_t tid, uint16_t sid, uint32_t game,
                                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                     const bool natures[25], const bool powers[16],
                                                     int shadowIndex);

/// A non-shadow (staticType 8) or Channel (9) search; NULL if the template
/// isn't one.
PFGameCubeSearchHandle pf_gamecubeSearchStatic_start(uint8_t method, bool unset,
                                                     uint16_t tid, uint16_t sid, uint32_t game,
                                                     uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                                     const uint8_t ivMin[6], const uint8_t ivMax[6],
                                                     const bool natures[25], const bool powers[16],
                                                     int staticType, int staticIndex);

int pf_gamecubeSearch_progress(PFGameCubeSearchHandle handle);
bool pf_gamecubeSearch_done(PFGameCubeSearchHandle handle);
PFSearcherState *pf_gamecubeSearch_getResults(PFGameCubeSearchHandle handle, int *outCount);
void pf_gamecubeSearch_cancel(PFGameCubeSearchHandle handle);
void pf_gamecubeSearch_free(PFGameCubeSearchHandle handle);

// MARK: - PokeSpot Generator

typedef struct {
    uint32_t advances;
    uint32_t encounterAdvances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t specie;
} PFPokeSpotState;

PFPokeSpotState *pf_pokeSpotGenerate(uint32_t seedFood, uint32_t seedEncounter,
                                      uint32_t initialAdvances, uint32_t maxAdvances, uint32_t offset,
                                      uint32_t initialAdvancesEncounter, uint32_t maxAdvancesEncounter, uint32_t offsetEncounter,
                                      uint16_t tid, uint16_t sid, uint32_t game,
                                      int pokeSpotIndex,
                                      uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                      const uint8_t ivMin[6], const uint8_t ivMax[6],
                                      const bool natures[25], const bool powers[16],
                                      const bool encounterSlots[12],
                                      int *outCount);

PFEncounterArea *pf_getPokeSpotEncounters(int *outCount);

// MARK: - Seed Searchers (GameCube)

typedef void *PFSeedSearchHandle;

PFSeedSearchHandle pf_coloSeedSearch_start(uint8_t lead, uint8_t trainer, int threads);
PFSeedSearchHandle pf_galesSeedSearch_start(uint16_t enemyHP0, uint16_t enemyHP1,
                                             uint16_t playerHP0, uint16_t playerHP1,
                                             uint8_t enemyIndex, uint8_t playerIndex,
                                             int threads);
PFSeedSearchHandle pf_channelSeedSearch_start(const uint8_t *pattern, int patternLength, int threads);

int pf_seedSearch_progress(PFSeedSearchHandle handle);
bool pf_seedSearch_done(PFSeedSearchHandle handle);
uint32_t *pf_seedSearch_getResults(PFSeedSearchHandle handle, int *outCount);
void pf_seedSearch_cancel(PFSeedSearchHandle handle);
void pf_seedSearch_free(PFSeedSearchHandle handle);

// MARK: - XD/Colo ID Generator

PFIDState *pf_idGenerate3_XDColo(uint32_t seed,
                                  uint32_t initialAdvances, uint32_t maxAdvances,
                                  int *outCount);

// MARK: - Jirachi Pattern

uint8_t *pf_jirachiPattern(uint32_t seed, uint32_t targetAdvance, uint32_t bruteForce, int *outCount);
uint32_t pf_computeJirachiSeed(uint32_t seed);

// MARK: - ID Searcher Gen 4 (Async)

typedef void *PFIDSearch4Handle;

PFIDSearch4Handle pf_idSearch4_start(bool infinite, uint16_t year,
                                      uint32_t minDelay, uint32_t maxDelay,
                                      uint16_t targetTID, bool filterTID,
                                      uint16_t targetSID, bool filterSID,
                                      uint16_t targetTSV, bool filterTSV);

int pf_idSearch4_progress(PFIDSearch4Handle handle);
bool pf_idSearch4_done(PFIDSearch4Handle handle);
PFIDState4 *pf_idSearch4_getResults(PFIDSearch4Handle handle, int *outCount);
void pf_idSearch4_cancel(PFIDSearch4Handle handle);
void pf_idSearch4_free(PFIDSearch4Handle handle);

// MARK: - Seed Verification Tools (Gen 4)
char *pf_coinFlips(uint32_t seed);
char *pf_getCalls(uint32_t seed, uint8_t skips);

/// HeartGold/SoulSilver's roamers on loading a game from `seed`: each
/// active one (Raikou, Entei, Latias/Latios) moves to a new route, rolling
/// again while it's the route it was on (`routes`, 0 for unknown). Returns
/// the PRNG advances that takes, which come before Elm and Irwin's calls;
/// `outRoutes` gets each one's new route (0 when inactive).
uint8_t pf_hgssRoamer(uint32_t seed, const bool roamers[3], const uint8_t routes[3], uint8_t outRoutes[3]);

/// Gen 3's PRNG (PokéRNG): the advances from `from` to `to`.
uint32_t pf_lcrngDistance(uint32_t from, uint32_t to);

/// PokéFinder's IV checker for any species: the IVs its stats at each
/// level allow, with `game`'s base stats (fresh catches have no EVs).
/// `outMasks[i]` has bit n set when IV n fits stat i. `characteristic` and
/// `hiddenPower` narrow it (255 for none). False if `specie` isn't in the
/// game.
bool pf_calcIVs(uint32_t game, uint16_t specie, uint8_t form,
                const uint8_t *levels, const uint16_t *stats, int count,
                uint8_t nature, uint8_t characteristic, uint8_t hiddenPower,
                uint32_t outMasks[6]);

/// `game`'s base stats for `specie` (HP, Atk, Def, SpA, SpD, Spe); false if
/// it isn't in the game.
bool pf_baseStats(uint32_t game, uint16_t specie, uint8_t form, uint8_t out[6]);

/// How many forms `specie` has in `game`'s table (1 when only its base
/// one; 0 when it isn't in the game).
uint8_t pf_formCount(uint32_t game, uint16_t specie);

/// The species `game`'s table marks present, as PokéFinder's IV calculator
/// lists them. Free with pf_freeResults.
uint16_t *pf_presentSpecies(uint32_t game, int *outCount);

/// PokéFinder's next level: per stat, the first level above `level` at which
/// two of these IVs (bit n of `masks[i]` set for IV n) give different stats;
/// `level` itself when the IV is known or no level up to 100 does.
bool pf_nextLevel(uint32_t game, uint16_t specie, uint8_t form, const uint32_t masks[6],
                  uint8_t level, uint8_t nature, uint8_t out[6]);

/// PokéFinder's characteristic text for index 0–29 ("Loves to eat", …):
/// index / 5 picks the stat (HP, Atk, Def, Spe, SpA, SpD), index % 5 the
/// IV mod 5.
char *pf_getCharacteristic(uint8_t characteristic);

// MARK: - Gen 5 Generator State

typedef struct {
    uint32_t advances;
    uint32_t ivAdvances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t chatot;
} PFGeneratorState5;

typedef struct {
    uint32_t advances;
    uint32_t ivAdvances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
    uint8_t chatot;
} PFWildGeneratorState5;

typedef struct {
    uint32_t advances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6];
    uint8_t chatot;
} PFEggGeneratorState5;

typedef struct {
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
} PFIDState5;

// MARK: - Gen 5 Static Generator

PFGeneratorState5 *pf_staticGenerate5(uint64_t seed,
                                       uint32_t initialAdvances,
                                       uint32_t maxAdvances,
                                       uint32_t offset,
                                       uint32_t ivInitialAdvances, uint32_t ivMaxAdvances,
                                       uint8_t method,
                                       uint8_t lead,
                                       uint16_t tid, uint16_t sid,
                                       uint32_t game,
                                       int staticType, int staticIndex,
                                       // Profile5 fields
                                       uint64_t mac, const bool keypresses[9],
                                       uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                       bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                       bool memoryLink, bool shinyCharm,
                                       uint8_t dsType, uint8_t language,
                                       // Filter
                                       uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                       const uint8_t ivMin[6], const uint8_t ivMax[6],
                                       const bool natures[25], const bool powers[16],
                                       int *outCount);

// MARK: - Gen 5 Wild Generator

PFWildGeneratorState5 *pf_wildGenerate5(uint64_t seed,
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
                                         // Profile5 fields
                                         uint64_t mac, const bool keypresses[9],
                                         uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                         bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                         bool memoryLink, bool shinyCharm,
                                         uint8_t dsType, uint8_t language,
                                         // Filter
                                         uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                         const uint8_t ivMin[6], const uint8_t ivMax[6],
                                         const bool natures[25], const bool powers[16],
                                         const bool encounterSlots[12],
                                         int *outCount);

// MARK: - Gen 5 Egg Generator

PFEggGeneratorState5 *pf_eggGenerate5(uint64_t seed,
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
                                        // Profile5 fields
                                        uint64_t mac, const bool keypresses[9],
                                        uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                        bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                        bool memoryLink, bool shinyCharm,
                                        uint8_t dsType, uint8_t language,
                                        // Filter
                                        uint8_t filterGender, uint8_t filterAbility, uint8_t filterShiny,
                                        const uint8_t ivMin[6], const uint8_t ivMax[6],
                                        const bool natures[25], const bool powers[16],
                                        int *outCount);

// MARK: - Gen 5 ID Generator

PFIDState5 *pf_idGenerate5(uint64_t seed,
                             uint32_t initialAdvances,
                             uint32_t maxAdvances,
                             uint32_t pid, bool checkPID, bool checkXOR,
                             uint16_t tid, uint16_t sid,
                             uint32_t game,
                             // Profile5 fields
                             uint64_t mac, const bool keypresses[9],
                             uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                             bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                             bool memoryLink, bool shinyCharm,
                             uint8_t dsType, uint8_t language,
                             // ID Filter
                             uint16_t filterTID, bool hasTIDFilter,
                             uint16_t filterSID, bool hasSIDFilter,
                             int *outCount);

// MARK: - Gen 5 Encounter Data

PFEncounterArea *pf_getEncounters5(uint8_t encounter, uint32_t game,
                                    uint8_t season,
                                    uint16_t tid, uint16_t sid,
                                    uint64_t mac, const bool keypresses[9],
                                    uint8_t vcount, uint8_t gxstat, uint8_t vframe,
                                    bool skipLR, uint16_t timer0Min, uint16_t timer0Max,
                                    bool memoryLink, bool shinyCharm,
                                    uint8_t dsType, uint8_t language,
                                    int *outCount);

PFStaticTemplate *pf_getStaticEncounters5(int type, int *outCount);

// MARK: - Gen 5 Searcher Result Structs

typedef struct {
    PFDateTime dateTime;
    uint64_t initialSeed;
    uint16_t timer0;
    uint16_t buttons;
    uint32_t advances;
    uint32_t ivAdvances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t chatot;
} PFSearchResult5;

typedef struct {
    PFDateTime dateTime;
    uint64_t initialSeed;
    uint16_t timer0;
    uint16_t buttons;
    uint32_t advances;
    uint32_t ivAdvances;
    uint32_t pid;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
    uint8_t chatot;
} PFWildSearchResult5;

// MARK: - Gen 5 Async Searcher

typedef void *PFSearch5Handle;

PFSearch5Handle pf_staticSearch5_start(uint32_t initialAdvances, uint32_t maxAdvances,
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
                                        const bool natures[25], const bool powers[16]);

PFSearch5Handle pf_wildSearch5_start(uint32_t initialAdvances, uint32_t maxAdvances,
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
                                      const bool encounterSlots[12]);

int pf_search5_progress(PFSearch5Handle handle);
PFSearchResult5 *pf_search5_static_getResults(PFSearch5Handle handle, int *outCount);
PFWildSearchResult5 *pf_search5_wild_getResults(PFSearch5Handle handle, int *outCount);
void pf_search5_cancel(PFSearch5Handle handle);
void pf_search5_free(PFSearch5Handle handle);

// MARK: - Gen 8 Generator State

typedef struct {
    uint32_t ec;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t height;
    uint8_t weight;
    uint8_t level;
} PFGeneratorState8;

typedef struct {
    uint32_t ec;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t height;
    uint8_t weight;
    uint8_t encounterSlot;
    uint8_t level;
    uint16_t item;
    uint16_t specie;
    uint8_t form;
} PFWildGeneratorState8;

typedef struct {
    uint32_t ec;
    uint32_t pid;
    uint32_t advances;
    uint32_t seed;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t inheritance[6];
} PFEggGeneratorState8;

typedef struct {
    uint32_t advances;
    uint16_t tid;
    uint16_t sid;
    uint16_t tsv;
    uint32_t displayTID;
} PFIDState8;

typedef struct {
    uint32_t ec;
    uint32_t pid;
    uint32_t advances;
    uint8_t ivs[6];
    uint8_t nature;
    uint8_t ability;
    uint8_t gender;
    uint8_t shiny;
    uint8_t hiddenPower;
    uint8_t hiddenPowerStrength;
    uint8_t height;
    uint8_t weight;
    uint16_t eggMove;
    uint16_t item;
    uint16_t specie;
    uint8_t level;
} PFUndergroundState;

// MARK: - Gen 8 Static Generator

PFGeneratorState8 *pf_staticGenerate8(uint64_t seed0, uint64_t seed1,
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
                                       int *outCount);

// MARK: - Gen 8 Wild Generator

PFWildGeneratorState8 *pf_wildGenerate8(uint64_t seed0, uint64_t seed1,
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
                                         int *outCount);

// MARK: - Gen 8 Egg Generator

PFEggGeneratorState8 *pf_eggGenerate8(uint64_t seed0, uint64_t seed1,
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
                                       int *outCount);

// MARK: - Gen 8 ID Generator

PFIDState8 *pf_idGenerate8(uint64_t seed0, uint64_t seed1,
                             uint32_t initialAdvances, uint32_t maxAdvances,
                             uint16_t filterTID, bool hasTIDFilter,
                             uint16_t filterSID, bool hasSIDFilter,
                             uint32_t filterDisplayTID, bool hasDisplayFilter,
                             int *outCount);

// MARK: - Gen 8 Raid Generator

PFGeneratorState8 *pf_raidGenerate8(uint64_t seed,
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
                                     int *outCount);

// MARK: - Gen 8 Underground Generator

PFUndergroundState *pf_undergroundGenerate8(uint64_t seed0, uint64_t seed1,
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
                                             int *outCount);

// MARK: - Gen 8 Encounter Data

PFEncounterArea *pf_getEncounters8(uint8_t encounter, uint32_t game,
                                    uint16_t tid, uint16_t sid,
                                    bool nationalDex, bool shinyCharm, bool ovalCharm,
                                    int time, bool swarm, bool radar,
                                    uint16_t replacement0, uint16_t replacement1,
                                    int *outCount);

PFStaticTemplate *pf_getStaticEncounters8(int type, int *outCount);

#ifdef __cplusplus
}
#endif

#endif /* PFBridge_h */
