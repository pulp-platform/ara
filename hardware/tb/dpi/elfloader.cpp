#include <svdpi.h>

#include <cstring>
#include <string>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <assert.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <vector>
#include <map>
#include <iostream>
#include <stdint.h>

#define IS_ELF(hdr) \
  ((hdr).e_ident[0] == 0x7f && (hdr).e_ident[1] == 'E' && \
   (hdr).e_ident[2] == 'L'  && (hdr).e_ident[3] == 'F')

#define IS_ELF32(hdr) (IS_ELF(hdr) && (hdr).e_ident[4] == 1)
#define IS_ELF64(hdr) (IS_ELF(hdr) && (hdr).e_ident[4] == 2)

#define PT_LOAD 1
#define SHT_NOBITS 8
#define SHT_PROGBITS 0x1
#define SHT_GROUP 0x11

typedef struct {
  uint8_t  e_ident[16];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint32_t e_entry;
  uint32_t e_phoff;
  uint32_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} Elf32_Ehdr;

typedef struct {
  uint32_t sh_name;
  uint32_t sh_type;
  uint32_t sh_flags;
  uint32_t sh_addr;
  uint32_t sh_offset;
  uint32_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint32_t sh_addralign;
  uint32_t sh_entsize;
} Elf32_Shdr;

typedef struct
{
  uint32_t p_type;
  uint32_t p_offset;
  uint32_t p_vaddr;
  uint32_t p_paddr;
  uint32_t p_filesz;
  uint32_t p_memsz;
  uint32_t p_flags;
  uint32_t p_align;
} Elf32_Phdr;

typedef struct
{
  uint32_t st_name;
  uint32_t st_value;
  uint32_t st_size;
  uint8_t  st_info;
  uint8_t  st_other;
  uint16_t st_shndx;
} Elf32_Sym;

typedef struct {
  uint8_t  e_ident[16];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint64_t e_entry;
  uint64_t e_phoff;
  uint64_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} Elf64_Ehdr;

typedef struct {
  uint32_t sh_name;
  uint32_t sh_type;
  uint64_t sh_flags;
  uint64_t sh_addr;
  uint64_t sh_offset;
  uint64_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint64_t sh_addralign;
  uint64_t sh_entsize;
} Elf64_Shdr;

typedef struct {
  uint32_t p_type;
  uint32_t p_flags;
  uint64_t p_offset;
  uint64_t p_vaddr;
  uint64_t p_paddr;
  uint64_t p_filesz;
  uint64_t p_memsz;
  uint64_t p_align;
} Elf64_Phdr;

typedef struct {
  uint32_t st_name;
  uint8_t  st_info;
  uint8_t  st_other;
  uint16_t st_shndx;
  uint64_t st_value;
  uint64_t st_size;
} Elf64_Sym;

// address and size
std::vector<std::pair<uint64_t, uint64_t>> sections;
std::map<std::string, uint64_t> symbols;
// memory based address and content
std::map<uint64_t, std::vector<uint8_t>> mems;
uint64_t entry;
int section_index = 0;

static void write (uint64_t address, uint64_t len, uint8_t* buf) {
  uint64_t datum;
  std::vector<uint8_t> mem;
  for (int i = 0; i < len; i++) {
    mem.push_back(buf[i]);
  }
  mems.insert(std::make_pair(address, mem));
}

extern "C" {
  char get_section(long long* address, long long* len);
  char read_section(long long address, const svOpenArrayHandle buffer);
  void read_elf(const char* filename);
}

// Communicate the section address and len
// Returns:
// 0 if there are no more sections
// 1 if there are more sections to load
extern "C" char get_section(long long* address, long long* len) {
  if (section_index < sections.size()) {
    *address = sections[section_index].first;
    *len = sections[section_index].second;
    section_index++;
    return 1;
  } else {
    return 0;
  }
}

extern "C" char read_section(long long address, const svOpenArrayHandle buffer) {
  // get actual poitner
  void* buf = svGetArrayPtr(buffer);
  // check that the address points to a section
  assert(mems.count(address) > 0);
  // copy array
  int i = 0;
  for (auto &datum : mems.find(address)->second) {
    *((char *) buf + i) = datum;
    i++;
  }
  return 0;
}

extern "C" void read_elf(const char* filename) {
  int fd = open(filename, O_RDONLY);
  struct stat s;
  assert(fd != -1);
  if (fstat(fd, &s) < 0)
  abort();
  size_t size = s.st_size;

  char* buf = (char*)mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
  assert(buf != MAP_FAILED);
  close(fd);

  assert(size >= sizeof(Elf64_Ehdr));
  const Elf64_Ehdr* eh64 = (const Elf64_Ehdr*)buf;
  assert(IS_ELF32(*eh64) || IS_ELF64(*eh64));



  std::vector<uint8_t> zeros;
  std::map<std::string, uint64_t> symbols;

  #define LOAD_ELF(ehdr_t, phdr_t, shdr_t, sym_t) do { \
  ehdr_t* eh = (ehdr_t*)buf; \
  phdr_t* ph = (phdr_t*)(buf + eh->e_phoff); \
  entry = eh->e_entry; \
  assert(size >= eh->e_phoff + eh->e_phnum*sizeof(*ph)); \
  for (unsigned i = 0; i < eh->e_phnum; i++) { \
    if(ph[i].p_type == PT_LOAD && ph[i].p_memsz) { \
    if (ph[i].p_filesz) { \
      assert(size >= ph[i].p_offset + ph[i].p_filesz); \
      sections.push_back(std::make_pair(ph[i].p_paddr, ph[i].p_memsz)); \
      write(ph[i].p_paddr, ph[i].p_filesz, (uint8_t*)buf + ph[i].p_offset); \
    } \
    zeros.resize(ph[i].p_memsz - ph[i].p_filesz); \
    } \
  } \
  shdr_t* sh = (shdr_t*)(buf + eh->e_shoff); \
  assert(size >= eh->e_shoff + eh->e_shnum*sizeof(*sh)); \
  assert(eh->e_shstrndx < eh->e_shnum); \
  assert(size >= sh[eh->e_shstrndx].sh_offset + sh[eh->e_shstrndx].sh_size); \
  char *shstrtab = buf + sh[eh->e_shstrndx].sh_offset; \
  unsigned strtabidx = 0, symtabidx = 0; \
  for (unsigned i = 0; i < eh->e_shnum; i++) { \
    unsigned max_len = sh[eh->e_shstrndx].sh_size - sh[i].sh_name; \
    if ((sh[i].sh_type & SHT_GROUP) && strcmp(shstrtab + sh[i].sh_name, ".strtab") != 0 && strcmp(shstrtab + sh[i].sh_name, ".shstrtab") != 0) \
    assert(strnlen(shstrtab + sh[i].sh_name, max_len) < max_len); \
    if (sh[i].sh_type & SHT_PROGBITS) continue; \
    if (strcmp(shstrtab + sh[i].sh_name, ".strtab") == 0) \
      strtabidx = i; \
    if (strcmp(shstrtab + sh[i].sh_name, ".symtab") == 0) \
      symtabidx = i; \
  } \
  if (strtabidx && symtabidx) { \
    char* strtab = buf + sh[strtabidx].sh_offset; \
    sym_t* sym = (sym_t*)(buf + sh[symtabidx].sh_offset); \
    for (unsigned i = 0; i < sh[symtabidx].sh_size/sizeof(sym_t); i++) { \
      unsigned max_len = sh[strtabidx].sh_size - sym[i].st_name; \
      assert(sym[i].st_name < sh[strtabidx].  sh_size); \
      assert(strnlen(strtab + sym[i].st_name, max_len) < max_len); \
      symbols[strtab + sym[i].st_name] = sym[i].st_value; \
    } \
  } \
  } while(0)

  if (IS_ELF32(*eh64))
    LOAD_ELF(Elf32_Ehdr, Elf32_Phdr, Elf32_Shdr, Elf32_Sym);
  else
    LOAD_ELF(Elf64_Ehdr, Elf64_Phdr, Elf64_Shdr, Elf64_Sym);

  munmap(buf, size);
}